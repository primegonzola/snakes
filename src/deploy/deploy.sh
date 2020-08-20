#!/bin/bash

# enter env
python3 -m venv .venv && source .venv/bin/activate

# variables to be used
UNIQUE_FIX="$(dd if=/dev/urandom bs=6 count=1 2>/dev/null | base64 | tr '[:upper:]+/=' '[:lower:]abc')"
PROJECT_NAME="snakes"
LOCATION="westeurope"
VERSION_LABEL=v$(date +'%Y%m%d%M%S')
RESOURCE_GROUP="${PROJECT_NAME}-${VERSION_LABEL}"
EVENTHUB_NAMESPACE="${PROJECT_NAME}evhns${UNIQUE_FIX}"
EVENTHUB_NAME="${PROJECT_NAME}evh${UNIQUE_FIX}"
STORAGE_ACCOUNT_NAME="${PROJECT_NAME}sa${UNIQUE_FIX}"
FUNCTION_APP_NAME="${PROJECT_NAME}app${UNIQUE_FIX}"
FUNCTION_APP_PLAN_NAME="${PROJECT_NAME}asp${UNIQUE_FIX}"
CONTAINER_REGISTRY_NAME="${PROJECT_NAME}acr${UNIQUE_FIX}"

# get our subscription
SUBSCRIPTION_ID=$(az account show --query id --output tsv)

# create resource group
az group create \
    --location ${LOCATION} \
    --name ${RESOURCE_GROUP}

# create event hub namespace
az eventhubs namespace create \
    --resource-group ${RESOURCE_GROUP} \
    --location ${LOCATION} \
    --name ${EVENTHUB_NAMESPACE} \
    --sku Basic

# create event hub
az eventhubs eventhub create \
    --resource-group ${RESOURCE_GROUP} \
    --namespace-name ${EVENTHUB_NAMESPACE} \
    --name ${EVENTHUB_NAME} \
    --message-retention 1

# get connection string
EVENTHUB_CONNECTION_STRING=$(az eventhubs namespace authorization-rule keys list \
    --resource-group ${RESOURCE_GROUP} \
    --namespace ${EVENTHUB_NAMESPACE} \
    --name RootManageSharedAccessKey | jq -r ".primaryConnectionString")

# create storage account
az storage account create \
    --name ${STORAGE_ACCOUNT_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --location ${LOCATION} \
    --sku Standard_LRS

# get connection string
STORAGE_ACCOUNT_CONNECTION_STRING=$(az storage account show-connection-string \
    --resource-group ${RESOURCE_GROUP} \
    --name ${STORAGE_ACCOUNT_NAME} --query connectionString --output tsv)

# create container registry
az acr create \
    --resource-group ${RESOURCE_GROUP} \
    --location ${LOCATION} \
    --name ${CONTAINER_REGISTRY_NAME} \
    --admin-enabled true \
    --sku Basic

# oveeride function bindings
pushd ./processor
cp ./function-template.json ./function.json
sed -i.bak \
    -e "s|<eventhub-name>|${EVENTHUB_NAME}|" \
    function.json
popd

# create docker image
docker build -t ${PROJECT_NAME}:${VERSION_LABEL} .
# tag image
docker tag ${PROJECT_NAME}:${VERSION_LABEL} ${CONTAINER_REGISTRY_NAME}.azurecr.io/${PROJECT_NAME}:${VERSION_LABEL}
# log in ACR
az acr login --name ${CONTAINER_REGISTRY_NAME}
# push image
docker push ${CONTAINER_REGISTRY_NAME}.azurecr.io/${PROJECT_NAME}:${VERSION_LABEL}

# create app plan
az functionapp plan create \
    --resource-group ${RESOURCE_GROUP} \
    --name ${FUNCTION_APP_PLAN_NAME} \
    --location ${LOCATION} \
    --sku B1 \
    --is-linux

# create the function app
az functionapp create \
    --name ${FUNCTION_APP_NAME} \
    --storage-account ${STORAGE_ACCOUNT_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --plan ${FUNCTION_APP_PLAN_NAME} \
    --runtime python \
    --functions-version 3 \
    --deployment-container-image-name ${CONTAINER_REGISTRY_NAME}.azurecr.io/${PROJECT_NAME}:${VERSION_LABEL}

# enable msi
FUNCTION_APP_PRINCIPAL_ID=$(az functionapp identity assign \
    --resource-group ${RESOURCE_GROUP} \
    --name ${FUNCTION_APP_NAME} --query principalId --output tsv)

# azure propagation of principal id
echo "HACK: waiting for principal propagation"
sleep 60

# set proper permission for principal (Acr Pull)
az role assignment create \
    --role "AcrPull" \
    --assignee-object-id ${FUNCTION_APP_PRINCIPAL_ID} \
    --assignee-principal-type ServicePrincipal \
    --scope /subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ContainerRegistry/registries/${CONTAINER_REGISTRY_NAME}

# azure propagation of principal id
echo "HACK: waiting for principal role assignment"
sleep 60

# enable container
az functionapp config container set \
    --name ${FUNCTION_APP_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --docker-custom-image-name ${CONTAINER_REGISTRY_NAME}.azurecr.io/${PROJECT_NAME}:${VERSION_LABEL} \
    --docker-registry-server-url https://${CONTAINER_REGISTRY_NAME}.azurecr.io

# setup app settings
az functionapp config appsettings set \
    --name ${FUNCTION_APP_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --settings AzureWebJobsStorage="${STORAGE_ACCOUNT_CONNECTION_STRING}" EVENTHUB_CONNECTION_STRING="${EVENTHUB_CONNECTION_STRING}"

# install
pip install azure-eventhub

# create for latex`x`r
echo "python3 ./client.py \"${EVENTHUB_CONNECTION_STRING}\" \"${EVENTHUB_NAME}\"" > run.sh && chmod +x ./run.sh

# run test
./run.sh
