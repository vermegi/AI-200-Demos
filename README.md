# AI-200 Azure Demos

Hands-on demos for the Azure services and application patterns in the AI-200 learning path. This repository contains the walkthrough scripts and working sample applications; the Microsoft Learn exercise repository is included as a Git submodule.

## Demo Tracks

| Track | Focus | First walkthrough |
| --- | --- | --- |
| [1. Containers](1.%20Containers/) | Docker, Azure Container Registry (ACR), tagging, and App Service containers | [Container introduction](1.%20Containers/0.%20ContainersIntro.azcli) |
| [2. ACA](2.%20ACA/) | Build, deploy, manage, and scale apps on Azure Container Apps | [ACA demo](2.%20ACA/1.%20ACADemo.azcli) |
| [3. AKS](3.%20AKS/) | Configure, deploy to, and troubleshoot Azure Kubernetes Service | [AKS configuration](3.%20AKS/1.%20AKSDemo.azcli) |
| [4. Cosmos](4.%20Cosmos/) | Cosmos DB for NoSQL, queries, and vector search | [Cosmos DB demo](4.%20Cosmos/1.%20CosmosDemo.azcli) |
| [5. PostGreSQL](5.%20PostGreSQL/) | PostgreSQL vector search, AI agents, and query optimization | [PostgreSQL demo](5.%20PostGreSQL/1.%20PostGreSQLDemo.azcli) |
| [6. Redis](6.%20Redis/) | Azure Managed Redis data operations, pub/sub, and vector queries | [Redis demo](6.%20Redis/1.%20RedisDemo.azcli) |
| [7. Integrate](7.%20Integrate/) | Service Bus, Event Grid, Azure Functions, and Durable Functions | [Service Bus demo](7.%20Integrate/1.%20ServiceBusDemo.azcli) |
| [8. Secrets and Config](8.%20Secrets%20and%20Config/) | Key Vault and App Configuration | [Key Vault demo](8.%20Secrets%20and%20Config/1.%20KeyVaultDemo.azcli) |
| [9. Observe](9.%20Observe/) | OpenTelemetry, log analysis, dashboards, workbooks, and alerts | [OpenTelemetry demo](9.%20Observe/1.%20OpenTelemetryDemo.azcli) |

## Prerequisites

- An Azure subscription and permissions to deploy the resources and role assignments used by the demos.
- Azure CLI and PowerShell for the deployment and walkthrough scripts.
- Git, including submodule support.
- Install track-specific tools such as Docker, Python, or `kubectl` as needed by the sample you run.

The deployment and demos create billable Azure resources. Review the resources and expected costs for your subscription, and clean them up when finished.

## Getting Started

1. Clone the repository, then initialize the Microsoft Learn submodule that contains the sample zip files:

   ```powershell
   git submodule update --init --recursive
   ```

2. Review [`deploy/deploy-all.azcli`](deploy/deploy-all.azcli) and update its user hash, region, and required sample values. Do not commit real keys or connection strings. This script currently signs out and signs in with Azure CLI, then deploys the shared environment at subscription scope; make sure the resulting Azure CLI context targets the intended subscription.

3. From the repository root, run the PowerShell commands in `deploy/deploy-all.azcli` to deploy the environment. The script and deployment are a work in progress and may require adjustment for your account, permissions, and region. More deployment automation through Azure Developer CLI (`azd`) is planned but is not available yet; `deploy-all.azcli` is currently the best available whole-environment deployment path.

4. Open a track and follow its unsuffixed `.azcli` files in numeric order. These contain the actual steps for the Learn path samples.

## Sample Setup and Scripts

Tracks 2–9 include a `0. Setup.azcli` script that expands clean sample copies from zip files in `mslearn-azure-ai`. The sample folders in this repository may already contain modifications. Setup uses `Expand-Archive -Force` and can overwrite matching files, so do not run it over folders whose changes you want to keep. Track 1 (Containers) does not use this setup script.

Files with letter suffixes such as `1b`, `2a`, or `3c` are additional variants. Start with the matching unsuffixed walkthrough unless you specifically need a variant.

## Microsoft Learn Content

[`mslearn-azure-ai`](mslearn-azure-ai/) is linked to the upstream [MicrosoftLearning/mslearn-azure-ai](https://github.com/MicrosoftLearning/mslearn-azure-ai) repository. It contains the AI-200 lab instructions and source archives used by the setup scripts. The standalone walkthroughs and modified sample applications are in the numbered track folders above. See the [exercise site](https://microsoftlearning.github.io/mslearn-azure-ai/) for the course materials.