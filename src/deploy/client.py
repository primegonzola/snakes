#!/usr/bin/env python

# --------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License.txt in the project root for license information.
# --------------------------------------------------------------------------------------------

"""
Examples to show sending events with different options to an Event Hub asynchronously.
"""

# pylint: disable=C0111
import sys
import time
import asyncio
import os

from azure.eventhub.aio import EventHubProducerClient
from azure.eventhub.exceptions import EventHubError
from azure.eventhub import EventData

CONNECTION_STR = sys.argv[1]
EVENTHUB_NAME = sys.argv[2]

async def send_event_data_batch(producer):
    # Without specifying partition_id or partition_key
    # the events will be distributed to available partitions via round-robin.
    event_data_batch = await producer.create_batch()
    event_data_batch.add(EventData('Single message'))
    await producer.send_batch(event_data_batch)

async def run():

    producer = EventHubProducerClient.from_connection_string(
        conn_str=CONNECTION_STR,
        eventhub_name=EVENTHUB_NAME
    )
    async with producer:
        await send_event_data_batch(producer)


loop = asyncio.get_event_loop()
start_time = time.time()
loop.run_until_complete(run())
print("Send messages in {} seconds.".format(time.time() - start_time))
