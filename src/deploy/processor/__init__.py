import json
import logging
import azure.functions as func

def main(event: func.EventHubEvent):
    logging.info('Hello World!')
    body = event.get_body().decode('utf-8')
    logging.info('Body: ' + body)