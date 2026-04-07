# Azure Monitor & Log Analytics Onboarding Script<br>
This PowerShell script streamlines onboarding Azure resources into Azure Monitor and Log Analytics, helping you quickly centralize logs, enable diagnostics, and understand your monitoring coverage across a subscription.

## What This Script Does<br>
The script guides you through discovering (or creating) a Log Analytics Workspace (LAW), then scans your Azure subscription to connect supported resources, enable diagnostics, and export visibility into the results.
<details>
<summary>
High-Level Workflow<br>
</summary>
  
### 1. Discover or Create a Log Analytics Workspace (LAW)<br>

Scans the Azure subscription currently connected to PowerShell for existing Log Analytics Workspaces.<br><br>
Prompts you to choose:<br>
- Create a new LAW
- Use an existing LAW



If creating a new LAW:
- Option to create a new Resource Group (RG)
- Use an existing RG
  
Guided naming prompts for:
- Log Analytics Workspace
- Resource Group (if needed)


### 2. Select or Confirm the Target LAW

If using an existing LAW:
- The script lists all available workspaces
- You select which one to use


If creating a new LAW:
- The script provisions it using the naming inputs you provide




### 3. Scan Azure Resources in the Subscription

Enumerates all resources in the connected Azure subscription.<br>
For each resource, the script:
- Determines whether it is Azure Monitor–compatible
- Checks whether Diagnostic Settings are already enabled
- Checks whether it is already connected to a Log Analytics Workspace

### 4. Enable Monitoring & Diagnostics
For resources that support Azure Monitor:

- Connects the resource to the selected Log Analytics Workspace
- Enables Diagnostic Settings (logs)
- Skips resources that are:

Not Azure Monitor compatible
- Already configured (to avoid duplicates)  <br>
</details>

<details>
<summary>
Output: Resource Visibility Report (CSV)
</summary>
  <br>
At the end of the run, the script generates a downloadable CSV report that provides visibility into your environment.
 <br> <br>The CSV includes: <br>

- Whether the resource is Azure Monitor compatible <br>
- Whether Diagnostic Settings are enabled <br>
- Whether the resource is connected to a Log Analytics Workspace <br>
- Whether logs are actively being sent <br>

This makes it easy to:<br>
- Audit monitoring coverage<br>
- Identify gaps<br>
- Share results with security, compliance, or operations teams
</details>

<details>
<summary>
Benefits
</summary>
  <br>
- Simplifies Azure Monitor onboarding<br>
- Reduces manual configuration and guesswork<br>
- Provides clear, exportable visibility into monitoring state<br>
- Works across an entire Azure subscription<br>
</details>


<details>
<summary>
Ideal Use Cases
</summary>
<br>

- Cloud hygiene and observability audits<br>
- Standardizing diagnostics across environments<br>
</details>

<details>
<summary>
Requirements
</summary>
<br>
- Initial Azure subscription & Azure resources setup<br>
- Azure PowerShell (Az modules)<br><br>
Permissions to:<br>
- Read Azure resources<br>
- Create or manage Log Analytics Workspaces<br>
- Configure Diagnostic Settings<br>
</details>
