#!/bin/bash

# CloudWatch Error Search - S3 Final Fixed Edition
# Correctly extracts EC2 and ECS IDs from actual logStream patterns
# EC2: *-i-xxxxxxxxxxxxxxxxx or */*/*-i-xxxxxxxxxxxxxxxxx
# ECS: */*/task-id (32-char hex)

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   CloudWatch Error Search - S3 Resumable Edition      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Get AWS account ID and region
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region || echo "us-east-1")

echo -e "${BLUE}📋 AWS Account:${NC} $AWS_ACCOUNT_ID"
echo -e "${BLUE}🌍 AWS Region:${NC} $AWS_REGION"
echo ""

# Generate bucket name
BUCKET_NAME="cloudwatch-errors-${AWS_ACCOUNT_ID}-${AWS_REGION}"

# Check for existing search or start new one
echo -e "${BLUE}Checking for existing search...${NC}"

# Look for most recent incomplete search
EXISTING_SEARCH=$(aws s3 ls s3://$BUCKET_NAME/searches/ 2>/dev/null | grep "PRE" | tail -1 | awk '{print $2}' | tr -d '/')

if [ -n "$EXISTING_SEARCH" ]; then
    # Check if search is complete
    if aws s3 ls s3://$BUCKET_NAME/searches/$EXISTING_SEARCH/COMPLETE 2>/dev/null; then
        echo -e "${YELLOW}Found completed search: $EXISTING_SEARCH${NC}"
        echo ""
        echo "Do you want to:"
        echo "  1) Resume/Continue that search (recommended if it was incomplete)"
        echo "  2) Start a NEW search"
        read -p "Enter choice [1-2]: " RESUME_CHOICE
        
        if [ "$RESUME_CHOICE" = "1" ]; then
            TIMESTAMP=$EXISTING_SEARCH
            RESUME=true
        else
            TIMESTAMP=$(date +%Y%m%d_%H%M%S)
            RESUME=false
        fi
    else
        echo -e "${GREEN}Found incomplete search: $EXISTING_SEARCH${NC}"
        echo -e "${YELLOW}Resuming from where it left off...${NC}"
        TIMESTAMP=$EXISTING_SEARCH
        RESUME=true
    fi
else
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    RESUME=false
fi

S3_PREFIX="searches/$TIMESTAMP"

echo -e "${YELLOW}🪣 S3 Bucket:${NC} $BUCKET_NAME"
echo -e "${YELLOW}📁 S3 Prefix:${NC} $S3_PREFIX"
echo ""

# Check if bucket exists, create if not
echo -e "${BLUE}Checking S3 bucket...${NC}"
if aws s3 ls "s3://$BUCKET_NAME" 2>/dev/null; then
    echo -e "${GREEN}✓ Bucket exists${NC}"
else
    echo -e "${YELLOW}Creating S3 bucket...${NC}"
    
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb "s3://$BUCKET_NAME" --region "$AWS_REGION"
    else
        aws s3 mb "s3://$BUCKET_NAME" --region "$AWS_REGION" --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    
    # Add lifecycle policy
    cat > /tmp/lifecycle-policy.json <<EOF
{
    "Rules": [
        {
            "Id": "DeleteOldSearchResults",
            "Status": "Enabled",
            "Prefix": "searches/",
            "Expiration": {
                "Days": 30
            }
        }
    ]
}
EOF
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$BUCKET_NAME" \
        --lifecycle-configuration file:///tmp/lifecycle-policy.json 2>/dev/null || true
    
    rm /tmp/lifecycle-policy.json
    
    echo -e "${GREEN}✓ Bucket created with 30-day retention policy${NC}"
fi
echo ""

# Time range
START_TIME="2025-10-20T08:00:00Z"
END_TIME="2025-10-20T16:00:00Z"

echo -e "${BLUE}📅 Time Range:${NC} Oct 20, 2025, 4:00 AM - 12:00 PM ET"
echo -e "${BLUE}🌍 UTC Range:${NC} $START_TIME to $END_TIME"
echo ""

# Convert to milliseconds
START_MS=$(date -d "$START_TIME" +%s)000
END_MS=$(date -d "$END_TIME" +%s)000

# Use minimal local storage
TEMP_DIR="/tmp/cw_search_$$"
mkdir -p "$TEMP_DIR"

# Search patterns
PATTERNS=("500" "timeout" "timed out" "TimeoutError" "HTTP 5")

echo -e "${YELLOW}🔍 Searching for error patterns:${NC} ${PATTERNS[*]}"
echo ""

# Get log groups
if [ "$RESUME" = true ]; then
    # Download log group list from S3
    if aws s3 cp s3://$BUCKET_NAME/$S3_PREFIX/log_groups.txt $TEMP_DIR/log_groups.txt 2>/dev/null; then
        echo -e "${GREEN}✓ Loaded log group list from previous search${NC}"
        LOG_GROUPS=($(cat $TEMP_DIR/log_groups.txt))
    else
        echo -e "${RED}Error: Could not load previous search data${NC}"
        exit 1
    fi
    
    # Download progress file
    if aws s3 cp s3://$BUCKET_NAME/$S3_PREFIX/progress.txt $TEMP_DIR/progress.txt 2>/dev/null; then
        COMPLETED_GROUPS=$(cat $TEMP_DIR/progress.txt)
        echo -e "${GREEN}✓ Found $COMPLETED_GROUPS completed log groups${NC}"
    else
        COMPLETED_GROUPS=0
    fi
else
    # New search - ask user for scope
    echo -e "${BLUE}Choose search scope:${NC}"
    echo "  1) Search ALL log groups (comprehensive)"
    echo "  2) Search SPECIFIC log groups (faster)"
    echo ""
    read -p "Enter choice [1-2]: " SEARCH_CHOICE
    
    LOG_GROUPS=()
    
    if [ "$SEARCH_CHOICE" = "2" ]; then
        echo ""
        echo -e "${BLUE}📋 Available log groups:${NC}"
        echo "Fetching log groups..."
        
        ALL_LOG_GROUPS=$(aws logs describe-log-groups --query 'logGroups[*].logGroupName' --output text)
        
        i=1
        declare -A GROUP_MAP
        for lg in $ALL_LOG_GROUPS; do
            echo "  $i) $lg"
            GROUP_MAP[$i]=$lg
            i=$((i+1))
            if [ $i -gt 20 ]; then
                echo "  ... and more (showing first 20)"
                break
            fi
        done
        
        echo ""
        echo "Enter log group numbers (comma-separated, e.g., 1,3,5)"
        echo "Or press Enter to search ALL:"
        read -p "> " SELECTED
        
        if [ -n "$SELECTED" ]; then
            IFS=',' read -ra NUMS <<< "$SELECTED"
            for num in "${NUMS[@]}"; do
                num=$(echo $num | xargs)
                if [ -n "${GROUP_MAP[$num]}" ]; then
                    LOG_GROUPS+=("${GROUP_MAP[$num]}")
                fi
            done
            
            if [ ${#LOG_GROUPS[@]} -eq 0 ]; then
                echo -e "${RED}No valid selections. Searching all log groups...${NC}"
                LOG_GROUPS=($ALL_LOG_GROUPS)
            fi
        else
            LOG_GROUPS=($ALL_LOG_GROUPS)
        fi
    else
        echo ""
        echo -e "${YELLOW}📥 Fetching all log groups...${NC}"
        LOG_GROUPS=($(aws logs describe-log-groups --query 'logGroups[*].logGroupName' --output text))
    fi
    
    # Save log group list to S3
    printf "%s\n" "${LOG_GROUPS[@]}" > $TEMP_DIR/log_groups.txt
    aws s3 cp $TEMP_DIR/log_groups.txt s3://$BUCKET_NAME/$S3_PREFIX/log_groups.txt --quiet
    
    COMPLETED_GROUPS=0
    echo "0" > $TEMP_DIR/progress.txt
    aws s3 cp $TEMP_DIR/progress.txt s3://$BUCKET_NAME/$S3_PREFIX/progress.txt --quiet
fi

echo ""
echo -e "${GREEN}✓ Total log groups: ${#LOG_GROUPS[@]}${NC}"
if [ "$COMPLETED_GROUPS" -gt 0 ]; then
    echo -e "${GREEN}✓ Already completed: $COMPLETED_GROUPS${NC}"
    echo -e "${YELLOW}✓ Remaining: $((${#LOG_GROUPS[@]} - COMPLETED_GROUPS))${NC}"
fi
echo -e "${GREEN}✓ Results stream to S3 (low memory usage)${NC}"
echo ""

# Initialize counters
TOTAL_ERRORS=0
PROCESSED=$COMPLETED_GROUPS
TOTAL_GROUPS=${#LOG_GROUPS[@]}

echo -e "${GREEN}🔎 Searching log groups (one at a time, memory efficient)...${NC}"
echo ""

# Process each log group individually
for ((i=$COMPLETED_GROUPS; i<${#LOG_GROUPS[@]}; i++)); do
    LOG_GROUP="${LOG_GROUPS[$i]}"
    PROCESSED=$((i + 1))
    
    # Show progress
    PERCENT=$((PROCESSED * 100 / TOTAL_GROUPS))
    BAR_LENGTH=40
    FILLED=$((PERCENT * BAR_LENGTH / 100))
    BAR=$(printf "%${FILLED}s" | tr ' ' '█')
    EMPTY=$(printf "%$((BAR_LENGTH - FILLED))s" | tr ' ' '░')
    
    echo -ne "\r[${BAR}${EMPTY}] ${PERCENT}% (${PROCESSED}/${TOTAL_GROUPS}) "
    
    # Search this log group for all patterns
    GROUP_ERRORS=0
    
    for PATTERN in "${PATTERNS[@]}"; do
        # Query CloudWatch Logs
        RESULT=$(aws logs filter-log-events \
            --log-group-name "$LOG_GROUP" \
            --start-time "$START_MS" \
            --end-time "$END_MS" \
            --filter-pattern "$PATTERN" \
            --output json 2>/dev/null || echo '{"events":[]}')
        
        # Check if we got events
        EVENT_COUNT=$(echo "$RESULT" | jq '.events | length' 2>/dev/null || echo "0")
        
        if [ "$EVENT_COUNT" -gt 0 ]; then
            GROUP_ERRORS=$((GROUP_ERRORS + EVENT_COUNT))
            
            # Save this batch directly to S3 as individual file
            BATCH_FILE="batches/batch_$(printf "%05d" $PROCESSED)_${PATTERN// /_}.json"
            echo "$RESULT" | jq '.events' > $TEMP_DIR/batch.json
            aws s3 cp $TEMP_DIR/batch.json s3://$BUCKET_NAME/$S3_PREFIX/$BATCH_FILE --quiet
            rm $TEMP_DIR/batch.json
        fi
    done
    
    # Update total
    TOTAL_ERRORS=$((TOTAL_ERRORS + GROUP_ERRORS))
    
    # Update progress in S3
    echo "$PROCESSED" > $TEMP_DIR/progress.txt
    aws s3 cp $TEMP_DIR/progress.txt s3://$BUCKET_NAME/$S3_PREFIX/progress.txt --quiet
done

echo ""
echo ""

# Now consolidate all batches into final files
echo -e "${GREEN}📦 Consolidating results from batches...${NC}"

echo "[]" > $TEMP_DIR/all_errors.json

# Get list of batch files
BATCH_FILES=$(aws s3 ls s3://$BUCKET_NAME/$S3_PREFIX/batches/ 2>/dev/null | awk '{print $4}' || echo "")

if [ -n "$BATCH_FILES" ]; then
    BATCH_COUNT=$(echo "$BATCH_FILES" | wc -l)
    echo -e "${BLUE}Processing $BATCH_COUNT batch files...${NC}"
    
    BATCH_NUM=0
    for BATCH in $BATCH_FILES; do
        BATCH_NUM=$((BATCH_NUM + 1))
        echo -ne "\rProcessing batch $BATCH_NUM/$BATCH_COUNT..."
        
        # Download this batch
        aws s3 cp s3://$BUCKET_NAME/$S3_PREFIX/batches/$BATCH $TEMP_DIR/batch.json --quiet
        
        # Append to all_errors using jq
        jq -s '.[0] + .[1]' $TEMP_DIR/all_errors.json $TEMP_DIR/batch.json > $TEMP_DIR/merged.json
        mv $TEMP_DIR/merged.json $TEMP_DIR/all_errors.json
        
        rm $TEMP_DIR/batch.json
    done
    echo ""
fi

# Upload consolidated results
echo -e "${GREEN}📤 Uploading consolidated results to S3...${NC}"
aws s3 cp $TEMP_DIR/all_errors.json s3://$BUCKET_NAME/$S3_PREFIX/all_errors.json --quiet

# Extract resource IDs from logStream names using correct patterns
echo -e "${GREEN}🔍 Extracting AWS resource IDs from log streams...${NC}"

# EC2 instance IDs - extract from logStream field
# Pattern: anything ending with -i-xxxxxxxxxxxxxxxxx
# Examples: eventlog-application-app-i-0150b6dd2ed5f361c
#           some/path/prefix-i-0150b6dd2ed5f361c
jq -r '.[] | .logStreamName' $TEMP_DIR/all_errors.json 2>/dev/null | \
    grep -oE '\-i-[0-9a-f]{17}' | \
    sed 's/^-//' | \
    sort -u > $TEMP_DIR/ec2_instance_ids.txt || touch $TEMP_DIR/ec2_instance_ids.txt

# Also catch any instance IDs not preceded by a dash
jq -r '.[] | .logStreamName' $TEMP_DIR/all_errors.json 2>/dev/null | \
    grep -oE '(^|/)i-[0-9a-f]{17}' | \
    sed 's/^\///' | \
    sort -u >> $TEMP_DIR/ec2_instance_ids.txt || true

# Remove duplicates
sort -u $TEMP_DIR/ec2_instance_ids.txt -o $TEMP_DIR/ec2_instance_ids.txt
EC2_COUNT=$(wc -l < $TEMP_DIR/ec2_instance_ids.txt)

# ECS task IDs - extract from logStream field
# Pattern: */*/32-character-hex
# Example: jfi-prod-eft-ecs-logs/frontend/8e078702cf614e3a9426dafeaba23394
# We want to extract: 8e078702cf614e3a9426dafeaba23394

# Extract 32-character hex strings that appear after a slash
jq -r '.[] | .logStreamName' $TEMP_DIR/all_errors.json 2>/dev/null | \
    grep '/' | \
    grep -oE '[0-9a-f]{32}' | \
    sort -u > $TEMP_DIR/ecs_task_ids.txt || touch $TEMP_DIR/ecs_task_ids.txt

# Also look for ECS task IDs in paths with ecs in the name
jq -r '.[] | .logStreamName' $TEMP_DIR/all_errors.json 2>/dev/null | \
    grep -i 'ecs' | \
    awk -F'/' '{print $NF}' | \
    grep -E '^[0-9a-f]{32}$' | \
    sort -u >> $TEMP_DIR/ecs_task_ids.txt || true

# Remove duplicates
sort -u $TEMP_DIR/ecs_task_ids.txt -o $TEMP_DIR/ecs_task_ids.txt
ECS_COUNT=$(wc -l < $TEMP_DIR/ecs_task_ids.txt)

# Error type breakdown
HTTP500=$(jq -r '.[] | .message' $TEMP_DIR/all_errors.json 2>/dev/null | grep -ci "500" || echo "0")
TIMEOUT=$(jq -r '.[] | .message' $TEMP_DIR/all_errors.json 2>/dev/null | grep -ciE "(timeout|timed out)" || echo "0")

# Count unique log streams
UNIQUE_STREAMS=$(jq -r '.[] | .logStreamName' $TEMP_DIR/all_errors.json 2>/dev/null | sort -u | wc -l)

# Upload resource lists
aws s3 cp $TEMP_DIR/ec2_instance_ids.txt s3://$BUCKET_NAME/$S3_PREFIX/ec2_instance_ids.txt --quiet
aws s3 cp $TEMP_DIR/ecs_task_ids.txt s3://$BUCKET_NAME/$S3_PREFIX/ecs_task_ids.txt --quiet

# Save unique logstreams for reference
jq -r '.[] | .logStreamName' $TEMP_DIR/all_errors.json 2>/dev/null | sort -u > $TEMP_DIR/unique_logstreams.txt
aws s3 cp $TEMP_DIR/unique_logstreams.txt s3://$BUCKET_NAME/$S3_PREFIX/unique_logstreams.txt --quiet

# Create summary
cat > $TEMP_DIR/summary.txt <<EOF
CloudWatch Error Search Summary
================================
Date: $(date)
Time Range: Oct 20, 2025 4:00 AM - 12:00 PM ET
UTC Range: $START_TIME to $END_TIME
Search ID: $TIMESTAMP

Search Results
--------------
Log Groups Searched: $TOTAL_GROUPS
Total Error Events Found: $TOTAL_ERRORS
Unique Log Streams with Errors: $UNIQUE_STREAMS
  - HTTP 500 errors: $HTTP500
  - Timeout errors: $TIMEOUT

AWS Resources Affected (extracted from logStream names)
--------------------------------------------------------
EC2 Instances: $EC2_COUNT
ECS Tasks/Containers: $ECS_COUNT

LogStream Pattern Examples:
- EC2: eventlog-application-app-i-0150b6dd2ed5f361c
       pattern: *-i-xxxxxxxxxxxxxxxxx
- ECS: jfi-prod-eft-ecs-logs/frontend/8e078702cf614e3a9426dafeaba23394
       pattern: */*/32-char-hex-task-id

S3 Storage Location
-------------------
Bucket: $BUCKET_NAME
Prefix: $S3_PREFIX

Files Stored in S3
------------------
• all_errors.json - Complete error log events (JSON)
• ec2_instance_ids.txt - List of EC2 instance IDs
• ecs_task_ids.txt - List of ECS task IDs  
• unique_logstreams.txt - All unique logStream names
• summary.txt - This summary file
• log_groups.txt - List of searched log groups
• progress.txt - Progress tracking file
• batches/ - Individual batch files (can be deleted to save space)

Access Your Results
-------------------
AWS Console:
https://s3.console.aws.amazon.com/s3/buckets/$BUCKET_NAME?prefix=$S3_PREFIX/

AWS CLI Commands:
# List all files
aws s3 ls s3://$BUCKET_NAME/$S3_PREFIX/ --recursive

# Download all results
aws s3 sync s3://$BUCKET_NAME/$S3_PREFIX/ ./cloudwatch_errors_$TIMESTAMP/ --exclude "batches/*"

# View summary
aws s3 cp s3://$BUCKET_NAME/$S3_PREFIX/summary.txt - | cat

# View EC2 instances
aws s3 cp s3://$BUCKET_NAME/$S3_PREFIX/ec2_instance_ids.txt -

# View ECS tasks
aws s3 cp s3://$BUCKET_NAME/$S3_PREFIX/ecs_task_ids.txt -

# View unique logStream names
aws s3 cp s3://$BUCKET_NAME/$S3_PREFIX/unique_logstreams.txt -

# Download errors JSON
aws s3 cp s3://$BUCKET_NAME/$S3_PREFIX/all_errors.json ./all_errors.json

Cleanup (Optional)
------------------
# Delete batch files to save space
aws s3 rm s3://$BUCKET_NAME/$S3_PREFIX/batches/ --recursive

Note: Files will auto-delete after 30 days (S3 lifecycle policy)
EOF

aws s3 cp $TEMP_DIR/summary.txt s3://$BUCKET_NAME/$S3_PREFIX/summary.txt --quiet

# Mark as complete
echo "complete" > $TEMP_DIR/COMPLETE
aws s3 cp $TEMP_DIR/COMPLETE s3://$BUCKET_NAME/$S3_PREFIX/COMPLETE --quiet

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    RESULTS SUMMARY                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📊 Total Error Events:${NC} ${RED}$TOTAL_ERRORS${NC}"
echo -e "${BLUE}📊 Unique Log Streams:${NC} ${YELLOW}$UNIQUE_STREAMS${NC}"
echo -e "   └─ HTTP 500 errors: ${RED}$HTTP500${NC}"
echo -e "   └─ Timeout errors: ${RED}$TIMEOUT${NC}"
echo ""
echo -e "${BLUE}🖥️  EC2 Instances:${NC} ${YELLOW}$EC2_COUNT${NC}"
echo -e "${BLUE}📦 ECS Tasks:${NC} ${YELLOW}$ECS_COUNT${NC}"
echo ""

# Display resource IDs
if [ "$EC2_COUNT" -gt 0 ]; then
    echo -e "${GREEN}EC2 Instance IDs (from logStream pattern *-i-*):${NC}"
    cat $TEMP_DIR/ec2_instance_ids.txt | head -10 | while read line; do echo "  • $line"; done
    if [ "$EC2_COUNT" -gt 10 ]; then
        echo "  ... and $((EC2_COUNT - 10)) more (see S3)"
    fi
    echo ""
fi

if [ "$ECS_COUNT" -gt 0 ]; then
    echo -e "${GREEN}ECS Task IDs (from logStream pattern */*/<task-id>):${NC}"
    head -10 $TEMP_DIR/ecs_task_ids.txt | while read line; do echo "  • $line"; done
    if [ "$ECS_COUNT" -gt 10 ]; then
        echo "  ... and $((ECS_COUNT - 10)) more (see S3)"
    fi
    echo ""
fi

echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                  S3 STORAGE LOCATION                   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}🪣 S3 Bucket:${NC} $BUCKET_NAME"
echo -e "${BLUE}📁 S3 Prefix:${NC} $S3_PREFIX"
echo ""
echo -e "${YELLOW}🌐 AWS Console:${NC}"
echo "   https://s3.console.aws.amazon.com/s3/buckets/$BUCKET_NAME?prefix=$S3_PREFIX/"
echo ""
echo -e "${YELLOW}📄 Quick Access Commands:${NC}"
echo ""
echo -e "${GREEN}# View summary:${NC}"
echo "   aws s3 cp s3://$BUCKET_NAME/$S3_PREFIX/summary.txt -"
echo ""
echo -e "${GREEN}# View EC2 instances:${NC}"
echo "   aws s3 cp s3://$BUCKET_NAME/$S3_PREFIX/ec2_instance_ids.txt -"
echo ""
echo -e "${GREEN}# View ECS tasks:${NC}"
echo "   aws s3 cp s3://$BUCKET_NAME/$S3_PREFIX/ecs_task_ids.txt -"
echo ""
echo -e "${GREEN}# Download results:${NC}"
echo "   aws s3 sync s3://$BUCKET_NAME/$S3_PREFIX/ ./cloudwatch_errors_$TIMESTAMP/ --exclude 'batches/*'"
echo ""

# Recommendations
if [ "$TOTAL_ERRORS" -gt 0 ]; then
    echo -e "${YELLOW}💡 Recommendations:${NC}"
    
    if [ "$TIMEOUT" -gt "$HTTP500" ]; then
        echo "  ⚠  High timeout rate detected!"
        echo "     → Check service timeouts and retry policies"
    elif [ "$HTTP500" -gt 10 ]; then
        echo "  ⚠  High 5xx error rate detected!"
        echo "     → Review application logs and recent deployments"
    fi
    
    if [ "$EC2_COUNT" -gt 0 ]; then
        echo "     → Review EC2 instance health for the IDs listed above"
    fi
    
    if [ "$ECS_COUNT" -gt 0 ]; then
        echo "     → Review ECS task health for the task IDs listed above"
    fi
    echo ""
fi

# Clean up temp directory
rm -rf $TEMP_DIR

echo -e "${GREEN}✅ Search complete! Results stored in S3${NC}"
echo -e "${BLUE}ℹ️  Resource IDs extracted using custom logStream patterns${NC}"
echo -e "${BLUE}ℹ️  Files will auto-delete from S3 after 30 days${NC}"
echo ""
