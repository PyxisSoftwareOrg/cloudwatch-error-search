# CloudWatch Error Search - CloudShell Package

## 📦 What's Inside

This package contains everything you need to search CloudWatch logs using AWS CloudShell - **no local installation required!**

### Files Included (5 total):

1. **cloudshell_search.sh** - The main script (all you need to run!)
2. **START_HERE_CLOUDSHELL.md** - Start here! Quick overview and setup
3. **QUICKSTART_CLOUDSHELL.md** - 1-page quick start guide
4. **CLOUDSHELL_README.md** - Complete documentation
5. **CLOUDSHELL_VS_LOCAL.md** - Why CloudShell is simpler

---

## 🚀 Quick Start (2 Minutes)

### Step 1: Extract This Package
Unzip/extract the downloaded file to access the contents.

### Step 2: Open AWS CloudShell
1. Log into AWS Console
2. Click the **>_** (CloudShell) icon in the top navigation bar
3. Wait for CloudShell to initialize

### Step 3: Upload the Script
- Click **Actions** → **Upload file**
- Select **cloudshell_search.sh** from the extracted folder

### Step 4: Run It
```bash
chmod +x cloudshell_search.sh
./cloudshell_search.sh
```

### Step 5: Follow the Prompts
- Choose to search all or specific log groups
- Wait for results (10-30 minutes)
- Review the summary automatically displayed

**That's it!** ✅

---

## 📖 Documentation

- **New to this?** Read **START_HERE_CLOUDSHELL.md** first
- **Want quick instructions?** See **QUICKSTART_CLOUDSHELL.md**
- **Need detailed help?** Check **CLOUDSHELL_README.md**
- **Wondering why CloudShell?** Read **CLOUDSHELL_VS_LOCAL.md**

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

## 📞 Need Help?

All documentation is included in this package. Start with **START_HERE_CLOUDSHELL.md** for the fastest path to results!

---

**Ready? Open CloudShell and upload the script!**
