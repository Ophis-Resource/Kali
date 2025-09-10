#!/bin/bash

# Define associative array with folder names and associated tools
declare -A folders=(
  ["01_Vulnerability-Scanners"]="vulmap vulscan grype syft dockle clair clair-scanner anchore-engine deepce rapidscan Sn1per fuzzapi fuzzdb XSStrike w3af golismero Corsy ReconDog Sublist3r pyfiscan"
  ["02_DDoS-Tools"]="DDOS DDoS DDoS-Ripper DDoS-Scripts DDos-attack DDos-Attack DDoSPacket DoS DoS-Tool DOS.PY dos dos-attack GoldenEye Http-Dos-Attack-Tool HULK MHDDoS Python-SYN-Flood-Attack-Tool"
  ["03_Docker-Security"]="dockle docker-bench-security amicontained dagda syft grype anchore-engine clair clair-scanner runc deepce"
  ["04_Pentesting-Tools"]="BloodHound XAttacker king-phisher botb Sn1per jok3r gophish ptf pimpmykali lynis"
  ["05_Recon-OSINT"]="Sublist3r ReconDog fuzzdb ggshield ldapdomaindump fuzzapi CyberChef goldeneye pyfiscan"
  ["06_Exploitation"]="dotdotpwn XSStrike Pompem Destroyer"
  ["07_Secrets-Auditing"]="SecretScanner ggshield"
  ["08_Scripts-Others"]="gitclone.sh githubinstallation.sh useful-repos.sh cfssl bin CDK nginx fiberfox scapy turbo-attack vault ThreatMapper"
)

for folder in "${!folders[@]}"; do
  mkdir -p "$folder"
  for tool in ${folders[$folder]}; do
    if [ -e "$tool" ]; then
      mv "$tool" "$folder/"
    fi
  done
done

echo "✅ Tools organized successfully!"
