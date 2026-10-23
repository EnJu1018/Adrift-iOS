#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
contract_tmp=$(mktemp -d /tmp/adrift-contract.XXXXXX)
trap 'rm -rf "$contract_tmp"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
  Adrift/Config/APIConfig.swift Adrift/Stores/TokenStore.swift \
  Adrift/Models/{APIResponse,AuthResponse,User,Diary,Friend}.swift \
  Adrift/Services/{APIClient,AuthService,DiaryService,FriendService,UserService}.swift \
  Tests/ContractChecks.swift -o "$contract_tmp/contracts"
"$contract_tmp/contracts"
xcrun swiftc -swift-version 5 -parse-as-library \
  Adrift/ViewModels/AppRefreshManager.swift Tests/RefreshChecks.swift -o "$contract_tmp/refresh"
"$contract_tmp/refresh"
