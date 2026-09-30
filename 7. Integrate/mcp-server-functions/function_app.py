import azure.functions as func
import json
import logging

# Initialize the FunctionApp instance that registers all trigger functions
app = func.FunctionApp()

# Define an MCP tool trigger that exposes "summarize_text" to MCP clients.
# toolProperties defines the input schema: a single "text" string parameter.
@app.generic_trigger(
    arg_name="context",
    type="mcpToolTrigger",
    toolName="summarize_text",
    description="Summarize a block of text into key points",
    toolProperties='[{"propertyName": "text", "propertyType": "string", "description": "The text to summarize"}]'
)
def summarize_text(context: str) -> str:
    # Log the raw payload for debugging
    logging.info(f"summarize_text raw context: {context}")
    # Parse the outer request envelope sent by the MCP client
    request = json.loads(context)
    logging.info(f"summarize_text parsed request: {request}")
    # Extract the tool arguments from the request
    arguments = request.get("arguments", {})
    # Retrieve the "text" property defined in toolProperties
    text = arguments.get("text", "")

    # In a real implementation, call an Azure AI service here
    summary = f"Summary of {len(text.split())} words: {text[:100]}..."

    # Return a JSON response; the "content" field is displayed to the MCP client
    return json.dumps({"content": summary})

# Define a second MCP tool trigger that exposes "classify_document" to MCP clients.
# toolProperties defines two input parameters: "text" and "categories".
@app.generic_trigger(
    arg_name="context",
    type="mcpToolTrigger",
    toolName="classify_document",
    description="Classify a document into a category",
    toolProperties='[{"propertyName": "text", "propertyType": "string", "description": "The document text to classify"}, {"propertyName": "categories", "propertyType": "string", "description": "Comma-separated list of possible categories"}]'
)
def classify_document(context: str) -> str:
    # Log the raw payload for debugging
    logging.info(f"classify_document raw context: {context}")
    # Parse the outer request envelope sent by the MCP client
    request = json.loads(context)
    logging.info(f"classify_document parsed request: {request}")
    # Extract the tool arguments from the request
    arguments = request.get("arguments", {})
    # Retrieve the "text" and "categories" properties defined in toolProperties
    text = arguments.get("text", "")
    categories = arguments.get("categories", "general")

    # In a real implementation, call an Azure AI service here
    # Split the comma-separated categories string into a list
    category_list = [c.strip() for c in categories.split(",")]
    # Select the first category as the classification result
    selected_category = category_list[0] if category_list else "unknown"

    # Return a JSON response with the classification result
    return json.dumps({
        "content": f"Classification: {selected_category}",
        "category": selected_category
    })