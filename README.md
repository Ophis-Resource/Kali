Azure Pipeline triggered (manual)
       │
       ▼
InstallDependencies stage
       │
       ├─ Checks required tools (whois, nslookup, ping, curl)
       └─ Installs missing tools
       │
       ▼
WhoisScan stage
       ├─ whois_scan.sh
       │   ├─ Logs: tools/logs/whois.log
       │   └─ Output: tools/output/whois_output.txt
       │
       ▼
PingScan stage
       ├─ ping_scan.sh
       │   ├─ Logs: tools/logs/ping.log
       │   └─ Output: tools/output/ping_output.txt
       │
       ▼
NslookupScan stage
           ├─ nslookup_scan.sh
           │   ├─ Logs: tools/logs/nslookup.log
           │   └─ Output: tools/output/nslookup_output.txt
           │
           ▼
       Pipeline completes
