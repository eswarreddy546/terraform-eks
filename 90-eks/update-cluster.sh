# #!/bin/bash

# # Auto-fix CRLF issue
# sed -i 's/\r$//' "$0" 2>/dev/null

# #########
# # Colors
# #########
# R="\e[31m"
# G="\e[32m"
# Y="\e[33m"
# N="\e[0m"

# #########
# # Config
# #########
# CLUSTER_NAME="roboshop-dev"
# AWS_REGION="us-east-1"

# EKS_TARGET_VERSION="$1"

# LOGS_FOLDER="/home/ec2-user/eks-upgrade"
# SCRIPT_NAME=$(basename "$0" .sh)
# LOG_FILE="$LOGS_FOLDER/$SCRIPT_NAME.log"

# mkdir -p "$LOGS_FOLDER"
# echo "Script started at: $(date)" | tee -a "$LOG_FILE"

# #########
# # Validate args
# #########
# if [ "$#" -ne 1 ]; then
#   echo -e "${R}Usage:${N} $0 <EKS_TARGET_VERSION>" | tee -a "$LOG_FILE"
#   exit 1
# fi

# #########
# # AWS check
# #########
# aws sts get-caller-identity &>/dev/null
# if [ $? -ne 0 ]; then
#   echo -e "${R}AWS credentials not working${N}" | tee -a "$LOG_FILE"
#   exit 1
# fi

# #########
# # Helper
# #########
# VALIDATE() {
#   if [ "${1:-1}" -ne 0 ]; then
#     echo -e "$2 ... ${R}FAILURE${N}" | tee -a "$LOG_FILE"
#     exit 1
#   else
#     echo -e "$2 ... ${G}SUCCESS${N}" | tee -a "$LOG_FILE"
#   fi
# }

# #########
# # Fetch addons
# #########
# ADDONS=$(aws eks list-addons \
#   --cluster-name "$CLUSTER_NAME" \
#   --region "$AWS_REGION" \
#   --query 'addons' \
#   --output text)

# #########
# # Current version
# #########
# CURRENT_CP_VERSION=$(aws eks describe-cluster \
#   --name "$CLUSTER_NAME" \
#   --region "$AWS_REGION" \
#   --query 'cluster.version' \
#   --output text)

# VALIDATE $? "Fetch current control plane version"

# echo -e "Current: ${Y}$CURRENT_CP_VERSION${N}" | tee -a "$LOG_FILE"
# echo -e "Target : ${Y}$EKS_TARGET_VERSION${N}" | tee -a "$LOG_FILE"

# #########
# # Version validation
# #########
# CUR_MAJOR=$(echo "$CURRENT_CP_VERSION" | cut -d. -f1)
# CUR_MINOR=$(echo "$CURRENT_CP_VERSION" | cut -d. -f2)
# TGT_MAJOR=$(echo "$EKS_TARGET_VERSION" | cut -d. -f1)
# TGT_MINOR=$(echo "$EKS_TARGET_VERSION" | cut -d. -f2)

# if [[ -z "$CUR_MAJOR" || -z "$CUR_MINOR" || -z "$TGT_MAJOR" || -z "$TGT_MINOR" ]]; then
#   echo -e "${R}Version parsing failed${N}" | tee -a "$LOG_FILE"
#   exit 1
# fi

# if [[ "$CUR_MAJOR" != "$TGT_MAJOR" || $((TGT_MINOR - CUR_MINOR)) -ne 1 ]]; then
#   echo -e "${R}Upgrade must be +1 minor only${N}" | tee -a "$LOG_FILE"
#   exit 1
# fi

# echo -e "${G}Version check passed${N}" | tee -a "$LOG_FILE"

# #########
# # Upgrade Control Plane
# #########
# aws eks update-cluster-version \
#   --name "$CLUSTER_NAME" \
#   --region "$AWS_REGION" \
#   --kubernetes-version "$EKS_TARGET_VERSION" &>> "$LOG_FILE"

# VALIDATE $? "Trigger control plane upgrade"

# #########
# # Wait for Control Plane
# #########
# MAX_RETRIES=60
# COUNT=0

# while [[ $COUNT -lt $MAX_RETRIES ]]; do
#   STATUS=$(aws eks describe-cluster \
#     --name "$CLUSTER_NAME" \
#     --region "$AWS_REGION" \
#     --query 'cluster.status' \
#     --output text)

#   VERSION=$(aws eks describe-cluster \
#     --name "$CLUSTER_NAME" \
#     --region "$AWS_REGION" \
#     --query 'cluster.version' \
#     --output text)

#   echo "Status=$STATUS Version=$VERSION" | tee -a "$LOG_FILE"

#   if [[ "$STATUS" == "ACTIVE" && "$VERSION" == "$EKS_TARGET_VERSION" ]]; then
#     echo -e "${G}Control plane upgraded${N}" | tee -a "$LOG_FILE"
#     break
#   fi

#   if [[ "$STATUS" == "FAILED" ]]; then
#     echo -e "${R}Control plane upgrade failed${N}" | tee -a "$LOG_FILE"
#     exit 1
#   fi

#   sleep 60
#   ((COUNT++))
# done

# if [[ $COUNT -eq $MAX_RETRIES ]]; then
#   echo -e "${R}Timeout waiting for control plane${N}" | tee -a "$LOG_FILE"
#   exit 1
# fi

# #########
# # Addon helpers
# #########
# addon_version() {
#   aws eks describe-addon \
#     --cluster-name "$CLUSTER_NAME" \
#     --addon-name "$1" \
#     --region "$AWS_REGION" \
#     --query 'addon.addonVersion' \
#     --output text 2>/dev/null || echo "UNKNOWN"
# }

# addon_status() {
#   aws eks describe-addon \
#     --cluster-name "$CLUSTER_NAME" \
#     --addon-name "$1" \
#     --region "$AWS_REGION" \
#     --query 'addon.status' \
#     --output text 2>/dev/null || echo "MISSING"
# }

# # ✅ FIXED: compatibility-aware version selection
# latest_addon_version() {
#   local addon="$1"
#   local cp_ver="$2"

#   aws eks describe-addon-versions \
#     --addon-name "$addon" \
#     --region "$AWS_REGION" \
#     --query "addons[].addonVersions[?compatibilities[?clusterVersion=='${cp_ver}']].addonVersion" \
#     --output text | tr '\t' '\n' | sort -V | tail -n1
# }

# #########
# # Upgrade Addons
# #########
# for addon in $ADDONS; do
#   CURRENT=$(addon_version "$addon")
#   LATEST=$(latest_addon_version "$addon" "$EKS_TARGET_VERSION")

#   if [[ -z "$LATEST" ]]; then
#     echo -e "${R}No compatible version found for $addon${N}" | tee -a "$LOG_FILE"
#     continue
#   fi

#   echo -e "${Y}$addon: $CURRENT -> $LATEST${N}" | tee -a "$LOG_FILE"

#   if [[ "$CURRENT" == "$LATEST" ]]; then
#     echo -e "${G}$addon already latest${N}" | tee -a "$LOG_FILE"
#     continue
#   fi

#   aws eks update-addon \
#     --cluster-name "$CLUSTER_NAME" \
#     --addon-name "$addon" \
#     --addon-version "$LATEST" \
#     --resolve-conflicts PRESERVE \
#     --region "$AWS_REGION" &>> "$LOG_FILE"

#   VALIDATE $? "Upgrade addon $addon"

#   COUNT=0
#   while [[ $COUNT -lt 30 ]]; do
#     STATUS=$(addon_status "$addon")
#     VERSION=$(addon_version "$addon")

#     echo "$addon status=$STATUS version=$VERSION" | tee -a "$LOG_FILE"

#     if [[ "$STATUS" == "ACTIVE" && "$VERSION" == "$LATEST" ]]; then
#       echo -e "${G}$addon upgraded${N}" | tee -a "$LOG_FILE"
#       break
#     fi

#     if [[ "$STATUS" == "FAILED" || "$STATUS" == "DEGRADED" ]]; then
#       echo -e "${R}$addon failed${N}" | tee -a "$LOG_FILE"
#       exit 1
#     fi

#     sleep 20
#     ((COUNT++))
#   done
# done

# echo -e "${G}EKS upgrade completed successfully 🚀${N}" | tee -a "$LOG_FILE"