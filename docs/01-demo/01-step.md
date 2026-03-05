# Demo 1 - Connected & Autonomous Agents

The scenario for this first demo is an Inventory Monitoring Agent.

It's encouraged to run through these steps live. If that is not possible, you can use this pre-recorded demo: [Demo 1 Video](Advanced%20Agent%20Dev%20with%20MCS%20-%20Demo%201.mp4)

We've also provided a solution that contains both demos: [Advanced Agentic Development Solution](/docs/ZavaApp_1_0_0_4.zip)

Follow these steps to re-create the demo.

1. Start off the demo by pulling up a blank New Agent in the M365 Copilot Agent Builder experience. Use this to point out that while this is technically using Copilot Studio, the capabilities are more limited. This sets the stage for why you would want to use the full version of Copilot Studio.

1. Transition to Copilot Studio. Start by entering the following prompt in the "what would you like to build" input:

```Monitors product inventory and creates product alerts```

1. Point out how it creates instructions for the agent and suggests knowledge sources, tools and triggers.
1. Also show how you can customize the model that the agent uses (keep it on GPT-5 though).
1. Select **Edit** next to the **Instructions** pane and replace the instructions with the instructions below:

```Todays date is: Now()
 
When asked to create product alerts, look for:

- Products have low stock (<20 units)
- For each product with low stock, find the total sales over the last 30 days


Reason to generate a tabular summary including:
- Product name
- Current stock
- Total sales over last 30 days
- Estimated days of stock remaining
- Suggest whether restock is needed (lest than 20 days left)

Only report products where action is needed.

IMPORTANT: When using the Dataverse MCP Server tool, ONLY use SQL keywords, SELECT, FROM, WHERE, SUM, GROUP BY, IN.  NEVER use CASE WHEN, HAVING,DATEADD, GETDATE, GETDATEUTC. Always Alias aggregate values

```

1. Locate the **Todays date is: Now()** part of the instruction.  The **Now()** part should be a Power Fx Expression so we can show how you can incorporate the Now function to get the current date which we'll need to accurately identify total sales for the last 30 days. Replace the Now() text and type a **forward slash /** and select the **PowerFx** option. Type **Now()** in the formula window and select **Insert**. Press **Save** to save the instructions.
1. Select the **Settings** tab. Scroll down to the knowledge section and disable **use general knowledge** and **use information from the web**. Point out that you have fine grain control to decide if your agent should only use the knowledge and tools you provide which is what we want for this scenario. Make sure to save these settings.
1. Now we'll show adding Dataverse knowledge. Go to the **Knowledge** tab and select **Add**.  Choose the **zava_Product**, **zava_Order**, **zava_OrderProduct** and **zava_ProductInventoryAdjustment** tables. Select **Add to agent**.
1. Test the agent by asking ```What product alerts are there?```. Show how the activity feed calls the knowledge sources to find the information. Mention that while you can use knowledge, there is also a Dataverse MCP server we could use for this instead which gives us more control over how it gets the data. 
1. Delete the knowledge you just added. Go to **Tools** - **Add Tool** - Select the **MCP** tab and select **Dataverse MCP**. Select **Add and configure**.
1. Show how you have fine grain control over the tools of the MCP server. Disable the ability to create, update, delete tables and records so this can only be used to search and query. Save these settings.
1. Test the agent again, this time using the MCP.  In the test window type  ```What product alerts are there?```.  Show the output.
1. Go back to the **Instructions** and click **Edit**. Replace the big about "products have low stock" with the following and click **Save**.

``` text

- Products have low stock (<20 units)
E.g. SELECT zava_productid, zava_productname, zava_inventoryquantity FROM zava_product WHERE zava_inventoryquantity < {threshold}

- For each product with low stock, find the total sales over the last 30 days
E.g SELECT zava_productname, SUM(zava_quantity) AS total_sales FROM zava_orderproduct WHERE zava_productname = '{product_guid}' AND createdon >= '{start_date}' GROUP BY zava_productname

```

This showcases how you can use "hints" to help tell the agent how to find the correct data, limiting what fields it returns, etc.  You can test again here if you want to show the difference.

## Add Autonomous Capability

Now that we have the base agent and it's connected to the Dataverse MCP, we want to make it autonomous. For the autonomous portion, the agent should run daily and send an email of product alerts each day.  

1. The first step is to add the Tool to send an email.  Go to the **Tools** section and select **Add tool**. Search for **Send email** and select the **Send an email V2** tool. Select **Add and configure**.
1. Replace the tool description with the following (make sure to point out why this is important as it helps tell the agent when this should be called):

``` text

This tool sends a product alert email when needed

```

1. Now you need to configure the inputs for this tool. Select the **Custom value** option next to the **TO** input. Click the **three dots...**. Select **Formula**. Type ```System.User.Email```. Click **Insert**
1. Select **Customize** next to the **Body** input. Replace the **Description** with the following:

``` text

An Html formatted list of product alerts with a summary, with pretty colorful formatting

```

1. Click **Save** to close out of this tool. 
1. Scroll down to the **Triggers** section and select **Add trigger**. Select the **Recurrence** trigger. Select **Next** twice.
1. Set the interval to 1 and the frequency to day.
1. Replace the trigger instructions with the following then click **Create**:

``` text

Execute the following steps:
1. Check for product alerts.
2. If there are product alerts, send a product alert email.

```

1. Point out how this uses Power Automate behind the scenes. Show how you can test the trigger by clicking on the Test button. Pull up your email to show the outcome.

## Showcase Deep Reasoning

1. Go to the agent settings and toggle on **Deep Reasoning**. Save the setting.
1. Put in the following in the test window:

``` text

First query for the product alerts, then using the code tool, create and excel file of this data with a graph of stock levels. 

```

1. Show the Excel file that the deep reasoning feature created.
1. Finally, show publishing this to Teams and using it there.
