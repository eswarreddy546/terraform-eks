# #!/bin/bash

# # Auto-fix CRLF issue
# sed -i 's/\r$//' "$0" 2>/dev/null

# ##### Colors ####
# R="\e[31m"
# G="\e[32m"
# Y="\e[33m"
# N="\e[0m"

# CLUSTER_NAME="roboshop-dev"
# AWS_REGION="us-east-1"

# CURRENT_NG_VERSION="$1"  # blue|green
# TARGET_NG_VERSION=""

# LOGS_FOLDER="/home/ec2-user/eks-upgrade"
# SCRIPT_NAME=$(basename "$0" .sh)
# LOG_FILE="$LOGS_FOLDER/$SCRIPT_NAME.log"

# mkdir -p "$LOGS_FOLDER"
# echo "Script started at: $(date)" | tee -a "$LOG_FILE"

# ######### Pre-checks #########
# command -v aws >/dev/null || { echo "aws not installed"; exit 1; }
# command -v kubectl >/dev/null || { echo "kubectl not installed"; exit 1; }
# command -v terraform >/dev/null || { echo "terraform not installed"; exit 1; }

# aws sts get-caller-identity >/dev/null 2>&1 || { echo "AWS not configured"; exit 1; }
# kubectl get nodes >/dev/null 2>&1 || { echo "kubectl not configured"; exit 1; }

# ######### Functions #########
# VALIDATE() {
#   if [ "${1:-1}" -ne 0 ]; then
#     echo -e "$2 ... ${R}FAILURE${N}" | tee -a "$LOG_FILE"
#     exit 1
#   else
#     echo -e "$2 ... ${G}SUCCESS${N}" | tee -a "$LOG_FILE"
#   fi
# }

# CONFIRM() {
#   echo -e "${Y}$1${N}" | tee -a "$LOG_FILE"
#   read -p "Type YES to continue: " ANS
#   if [[ "$ANS" != "YES" ]]; then
#     echo -e "${R}Aborted by user${N}" | tee -a "$LOG_FILE"
#     exit 1
#   fi
# }

# ######### Args validation #########
# if [[ $# -ne 1 ]]; then
#   echo -e "${R}Usage:${N} $0 <blue|green>" | tee -a "$LOG_FILE"
#   exit 1
# fi

# if [[ "$CURRENT_NG_VERSION" != "blue" && "$CURRENT_NG_VERSION" != "green" ]]; then
#   echo -e "${R}Value must be 'blue' or 'green'${N}" | tee -a "$LOG_FILE"
#   exit 1
# fi

# if [[ "$CURRENT_NG_VERSION" == "blue" ]]; then
#   TARGET_NG_VERSION="green"
# else
#   TARGET_NG_VERSION="blue"
# fi

# echo -e "${Y}Current nodegroup: $CURRENT_NG_VERSION${N}" | tee -a "$LOG_FILE"
# echo -e "${Y}Target  nodegroup: $TARGET_NG_VERSION${N}" | tee -a "$LOG_FILE"

# ######### Control plane version #########
# CP_VERSION=$(aws eks describe-cluster \
#   --name "$CLUSTER_NAME" \
#   --region "$AWS_REGION" \
#   --query 'cluster.version' \
#   --output text)

# VALIDATE $? "Fetch control plane version"
# echo -e "${Y}Control plane version: $CP_VERSION${N}" | tee -a "$LOG_FILE"

# ######### Detect kubelet version #########
# KUBELET_VER=$(kubectl get nodes -l "nodegroup=${CURRENT_NG_VERSION}" \
#   -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}' 2>/dev/null)

# if [[ -z "$KUBELET_VER" ]]; then
#   echo -e "${R}No nodes found with label nodegroup=${CURRENT_NG_VERSION}${N}" | tee -a "$LOG_FILE"
#   exit 1
# fi

# CURRENT_NG_K8S_VER=$(echo "$KUBELET_VER" | sed -E 's/^v([0-9]+\.[0-9]+).*/\1/')
# echo -e "${Y}Detected kubelet: $CURRENT_NG_K8S_VER${N}" | tee -a "$LOG_FILE"

# ######### Terraform vars #########
# ENABLE_BLUE=true
# ENABLE_GREEN=true

# if [[ "$CURRENT_NG_VERSION" == "green" ]]; then
#   NG_GREEN_VERSION="$CURRENT_NG_K8S_VER"
#   NG_BLUE_VERSION="$CP_VERSION"
# else
#   NG_BLUE_VERSION="$CURRENT_NG_K8S_VER"
#   NG_GREEN_VERSION="$CP_VERSION"
# fi

# echo -e "${Y}Plan: blue=$NG_BLUE_VERSION green=$NG_GREEN_VERSION${N}" | tee -a "$LOG_FILE"

# ######### STEP 1: Create target nodegroup #########
# terraform plan \
#   -var="eks_version=$CP_VERSION" \
#   -var="enable_blue=$ENABLE_BLUE" \
#   -var="enable_green=$ENABLE_GREEN" \
#   -var="eks_nodegroup_blue_version=$NG_BLUE_VERSION" \
#   -var="eks_nodegroup_green_version=$NG_GREEN_VERSION" | tee -a "$LOG_FILE"

# VALIDATE ${PIPESTATUS[0]} "Terraform plan (create target)"

# CONFIRM "Create target nodegroup?"

# terraform apply -auto-approve \
#   -var="eks_version=$CP_VERSION" \
#   -var="enable_blue=$ENABLE_BLUE" \
#   -var="enable_green=$ENABLE_GREEN" \
#   -var="eks_nodegroup_blue_version=$NG_BLUE_VERSION" \
#   -var="eks_nodegroup_green_version=$NG_GREEN_VERSION" | tee -a "$LOG_FILE"

# VALIDATE ${PIPESTATUS[0]} "Terraform apply (create target)"

# ######### Wait for nodes #########
# echo -e "${Y}Waiting for target nodes...${N}" | tee -a "$LOG_FILE"

# kubectl wait --for=condition=Ready node \
#   -l "nodegroup=${TARGET_NG_VERSION}" \
#   --timeout=30m 2>&1 | tee -a "$LOG_FILE"

# VALIDATE ${PIPESTATUS[0]} "Nodes ready"

# ######### Remove taints #########
# for n in $(kubectl get nodes -l "nodegroup=${TARGET_NG_VERSION}" -o name); do
#   kubectl taint "$n" upgrade=true:NoSchedule- >/dev/null 2>&1
# done

# ######### Drain old nodes #########
# CONFIRM "Drain current nodegroup ${CURRENT_NG_VERSION}?"

# kubectl cordon -l "nodegroup=${CURRENT_NG_VERSION}" | tee -a "$LOG_FILE"
# VALIDATE ${PIPESTATUS[0]} "Cordon"

# kubectl drain -l "nodegroup=${CURRENT_NG_VERSION}" \
#   --ignore-daemonsets \
#   --delete-emptydir-data \
#   --force \
#   --grace-period=60 \
#   --timeout=30m | tee -a "$LOG_FILE"

# VALIDATE ${PIPESTATUS[0]} "Drain"

# ######### Health check #########
# kubectl get pods -A | egrep -i "Pending|CrashLoopBackOff" || true

# ######### STEP 2: Delete old nodegroup #########
# if [[ "$CURRENT_NG_VERSION" == "blue" ]]; then
#   ENABLE_BLUE=false
# else
#   ENABLE_GREEN=false
# fi

# terraform plan \
#   -var="eks_version=$CP_VERSION" \
#   -var="enable_blue=$ENABLE_BLUE" \
#   -var="enable_green=$ENABLE_GREEN" \
#   -var="eks_nodegroup_blue_version=$NG_BLUE_VERSION" \
#   -var="eks_nodegroup_green_version=$NG_GREEN_VERSION" | tee -a "$LOG_FILE"

# VALIDATE ${PIPESTATUS[0]} "Terraform plan (delete old)"

# CONFIRM "Delete old nodegroup?"

# terraform apply -auto-approve \
#   -var="eks_version=$CP_VERSION" \
#   -var="enable_blue=$ENABLE_BLUE" \
#   -var="enable_green=$ENABLE_GREEN" \
#   -var="eks_nodegroup_blue_version=$NG_BLUE_VERSION" \
#   -var="eks_nodegroup_green_version=$NG_GREEN_VERSION" | tee -a "$LOG_FILE"

# VALIDATE ${PIPESTATUS[0]} "Terraform apply (delete old)"

# echo -e "${G}Blue/Green Nodegroup Upgrade Completed 🚀${N}" | tee -a "$LOG_FILE"