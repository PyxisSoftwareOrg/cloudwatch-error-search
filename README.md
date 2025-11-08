# CloudWatch Error Search - CloudShell Package

## 📦 What's Inside

This package contains everything you need to search CloudWatch logs using AWS CloudShell - **no local installation required!**

### Files Included (2 total):

1. **cloudshell_search_s3.sh** - The main script (all you need to run!)
2. **README.md** - Complete documentation

---

## 🚀 Quick Start (2 Minutes)

### Step 1: Download Script
Download cloudshell_search_s3.sh

### Step 2: Open AWS CloudShell
1. Log into AWS Console
2. Click the **>_** (CloudShell) icon in the top navigation bar
3. Wait for CloudShell to initialize

### Step 3: Upload the Script
- Click **Actions** → **Upload file**
- Select **cloudshell_search_s3.sh** from the extracted folder

### Step 4: Run It

```bash
chmod +x cloudshell_search_s3.sh
./cloudshell_search_s3.sh
```

### Step 5: Follow the Prompts
- Choose to search all or specific log groups
- Wait for results (10-30 minutes)
- Review the summary automatically displayed
- If you interrupt it before it finishes just re-run the script and it will pick up where it left off.

**That's it!** ✅

---

## 🎯 What It Does

Searches CloudWatch logs for:
- HTTP 500 errors
- Timeout errors
- Other 5xx errors

**Time Window:** Oct 20, 2025, 4:00 AM - 12:00 PM Eastern Time

**Extracts:**
- EC2 instance IDs
- ECS container/task IDs

**Generates:**
- Complete error log (JSON)
- List of affected resources
- Summary report with recommendations

# Modification Options
## Search patterns
PATTERNS=("500" "timeout" "timed out" "TimeoutError" "HTTP 5")

### EC2 instance IDs - extract from logStream field
    Pattern: anything ending with -i-xxxxxxxxxxxxxxxxx 
    Examples: eventlog-application-app-i-0150b6dd2ed5f361c
    some/path/prefix-i-0150b6dd2ed5f361c
```bash   
jq -r '.[] | .logStreamName' $TEMP_DIR/all_errors.json 2>/dev/null | \
    grep -oE '\-i-[0-9a-f]{17}' | \
    sed 's/^-//' | \
    sort -u > $TEMP_DIR/ec2_instance_ids.txt
```

### Also catch any instance IDs not preceded by a dash
```bash
jq -r '.[] | .logStreamName' $TEMP_DIR/all_errors.json 2>/dev/null | \
    grep -oE '(^|/)i-[0-9a-f]{17}' | \
    sed 's/^\///' | \
    sort -u >> $TEMP_DIR/ec2_instance_ids.txt
```
### ECS task IDs - extract from logStream field
    Pattern: */*/32-character-hex
    Example: jfi-prod-eft-ecs-logs/frontend/8e078702cf614e3a9426dafeaba23394
    We want to extract: 8e078702cf614e3a9426dafeaba23394

### Extract 32-character hex strings that appear after a slash
```bash
jq -r '.[] | .logStreamName' $TEMP_DIR/all_errors.json 2>/dev/null | \
    grep '/' | \
    grep -oE '[0-9a-f]{32}' | \
    sort -u > $TEMP_DIR/ecs_task_ids.txt
```

### Also look for ECS task IDs in paths with ecs in the name

```bash
jq -r '.[] | .logStreamName' $TEMP_DIR/all_errors.json 2>/dev/null | \
    grep -i 'ecs' | \
    awk -F'/' '{print $NF}' | \
    grep -E '^[0-9a-f]{32}$' | \
    sort -u >> $TEMP_DIR/ecs_task_ids.txt
```

---

## ✨ Why CloudShell?

- ✅ **No installation** - AWS CLI and jq pre-installed
- ✅ **No credentials** - Already authenticated
- ✅ **No troubleshooting** - Works out of the box
- ✅ **Just 1 script** - Simple and clean
- ✅ **Works everywhere** - Any browser, any OS

---

## 💡 Pro Tip

On your first run, choose option 1 (search all log groups) to get a complete picture. On subsequent runs, you can choose option 2 to target specific log groups for faster results.


---

**Ready? Open CloudShell and upload the script!**
