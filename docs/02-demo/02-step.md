# DEMO 2 - Multi-Agent and Agent Flows

This demo focuses on building a multi-agent scenario for warehouse management and inventory adjustments.

It's encouraged to run through these steps live. If that is not possible, you can use this pre-recorded demo: [Demo 2 Video](Advanced%20Agent%20Dev%20with%20MCS%20-%20Demo%202.mp4)

We've also provided a solution that contains both demos: [Advanced Agentic Development Solution](/docs/ZavaApp_1_0_0_4.zip)

## Setup main warehouse agent

1. Go to Copilot Studio and enter the following prompt to build a warehouse agent:

``` text

The warehouse agent monitors product inventory, processes delivery notes, and records inventory.

```

1. Go to the settings and disable general knowledge and knowledge from the web. Ensure the connected agent setting is on.
1. Change the model to GPT-4.1

## Add Connected Agent

1. Go to the Agents tab - select add agent - select the Inventory Agent you built in the previous demo

## Add Child Agent

1. Go to the AGents tab - select new child agent
1. Name this agent ```Product Inventory Adjustments```
1. Put the following for the description then save the child agent:

``` text

Creates product inventory adjustments (Sale or Restock) for products

```

1. Add the following instructions:

```text
Always provide a summary of all actions taken
```

1. Select **Add Knowledge** and choose the **zava_product** table.

## Add the Agent Flow

1. Go to the Product Inventory Adjustments Child Agent. Select **Tools** then **Add** and select the **Create Product Inventory Adjustment** agent flow (imported from the solution).
1. Paste the following in the **Description** field for the tool:

```text
Creates product inventory adjustments (Sale or Restock) for products
1. You must first search for the productid by product name (case-insensitive name search).
2. If 0 matches → ask for clarification (do not create adjustment).
3. If >1 matches → return disambiguation list (do not create adjustment).
4. Only proceed to create an adjustment after unambiguous product resolution.
```

1. Paste the following in the **zava_productid** input Description:

```text
 The zava_productid (GUID) of the Product to create a adjustment for. Allow the user to search for this using knowledge. Only use a GUID of the product - never the name.
 ```

 1. Paste the following in the **Quantity** input Description:

 ```text
 The adjustment quantity
 ```

 1. Paste the following in the **Adjustment Type** input Description:

```text
Restock/Return
```

1. Open the Agent Flow and showcase what it is doing
1. Test the Agent Flow by entering the following in the test window:

```text
I need to create a product inventory adjustment
Create a product inventory adjustment for the Zava Bucket Hat, restocking 10 units.
```

## Add a Multi-Modal Prompt

1. Go to **Tools** and select **Add Tool**. Choose the **Extract Delivery Note PDF Data** Prompt imported from the solution.

1. Test the prompt by putting the following in the test window:

`First(System.Activity.Attachments).Content`

```text
Here is a delivery note to process
```

## Add Computer Use Agent

This showcases using a Computer Use Agent that can enter in delivery note data in a website with no API.

1. Setup CUA

```yaml
kind: TaskDialog
inputs:
  - kind: AutomaticTaskInput
    propertyName: deliveryNoteData
    name: Delivery Note Data
    description: |-
      JSON of the delivery note in the following format:
      {
        "delivery_note_number": "",
        "date": "",
        "sender": {
          "name": "",
          "address": "",
          "contact": ""
        },
        "receiver": {
          "name": "",
          "address": "",
          "contact": ""
        },
        "items": [
          {
            "item_name": "",
            "description": "",
            "quantity": 0,
            "unit_price": 0.0
          }
        ],
        "total_quantity": 0,
        "total_amount": 0.0,
        "notes": ""
      }

modelDisplayName: Record Delivery in Warehouse System
modelDescription: Submits multiple delivered products into the Warehouse system
action:
  kind: InvokeComputerUsingAgentTaskAction
  connectionReference: blank_agent_zg8h1.shared_computeroperator.f1d70de82a9b4bbc8ca3056818d1eac6
  connectionProperties:
    mode: Maker

  operationId: ComputerOperatorInvokeMcpCua
  instructions: |-
    **Login**
    1. Open https://zavawarehousemgmt2.z13.web.core.windows.net/
    2. Besure to maximize the browser window
    3. Enter **Username** using the WarehouseLogin credentials (Username)
    4. Enter **Password** using the WarehouseLogin credentials (Password)
    5. Click **Login** - do not ask for confirmation at any stage.

    ### **Create New Delivery**
    1. Enter **Details:** `<DELIVERY DETAILS SUMMARY>`

    ### **Add Products**
    1. Product: `<PRODUCT NAME>`
    2. Units: <QUANTITY>

    ### **Submit**
    1. Click **Create Delivery & Generate Tasks**

    **IMPORTANT:**  Do not ask for confirmation at any stage - just proceed as instructed.
  inputType:
    properties:
      deliveryNoteData:
        displayName: Delivery Note Data
        description: |-
          JSON of the delivery note in the following format:
          {
            "delivery_note_number": "",
            "date": "",
            "sender": {
              "name": "",
              "address": "",
              "contact": ""
            },
            "receiver": {
              "name": "",
              "address": "",
              "contact": ""
            },
            "items": [
              {
                "item_name": "",
                "description": "",
                "quantity": 0,
                "unit_price": 0.0
              }
            ],
            "total_quantity": 0,
            "total_amount": 0.0,
            "notes": ""
          }
        isRequired: true
        type: String

  initializeContext:
    requestForInformationInput:
      assignedTo:
        acc79dc7-cab8-408a-932e-279cbbf8d60c:
          email: scottdurow@capowerplatform2512.onmicrosoft.com
          id: acc79dc7-cab8-408a-932e-279cbbf8d60c

      timeToCompleteInMinutes: 60
      version: 2

  credentialIds:
    - 01e4b8d6-8fc1-f011-8544-000d3a5ccb44
```

Sample Delivery Note JSON used to test (Extracted from sample PDF)

```text
{
  "delivery_note_number": "DN-2025-002",
  "date": "2025-11-12",
  "customer": {
    "name": "Alice Thompson",
    "contact": "+1-555-238-0011",
    "email": "alice.thompson@example.com",
    "address": "123 Maple Lane, Springfield, IL, 62704, USA"
  },
  "items": [
    {
      "item_name": "ActiveFlex T-Shirt - Navy",
      "productId": "ff955be1-e7c0-f011-8544-000d3a3b39a2",
      "quantity": 4,
      "unit_price": 39.99,
      "total_price": 159.96
    },
    {
      "item_name": "SmartFit Dress - Black",
      "productId": "7182ffed-e7c0-f011-8544-000d3a3b39a2",
      "quantity": 2,
      "unit_price": 89.99,
      "total_price": 179.98
    }
  ],
  "subtotal": 499.9,
  "tax": 39.99,
  "total_amount": 539.89,
  "delivery_instructions": "Please call customer if no one answers the door.",
  "status": "Pending",
  "delivered_by": "Emily Smith",
  "delivery_signature": ""
}
```

1. Go back to the **Overview** tab of the parent warehouse agent and replace the instructions with the following:

```text

Use /Product Inventory Adjustments to create product inventory adjustments.

Only run once per unique adjustment request

Always provide a summary of all actions taken

```
