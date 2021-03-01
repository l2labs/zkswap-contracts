# ZKSwap-contracts

## ZKSwap protocol
ZKSwap is a layer2 AMM dex based on ethereum, using zkspeed protocol:
1. support AMM related transactions (create_pair, add_liquidity, remove_liquidity, swap)
2. support pair token creation/management and enabling pair token transfer between L2 and L1
3. enabling liquidity token exit if in exodus mode
4. enable commit blocks feature - more blocks can be committed in one transaction 
5. enable proof aggeration verification feature    

the details are descirbed in the link:https://github.com/l2labs/zkswap-spec


## Reference
Smart contract audit report:
https://github.com/l2labs/zkswap-security-audit-certification


Many thanks to Matter Labs and zkSync team for their outstanding contributions to Layer2 ecosystem and ZK-Rollup technology. Based on their open source work, ZKSwap added a swap circuit and a high performance Layer2 zk proving system (using over100 high performance servers and 200 piece 2080Ti GPU Cards, and as far as we know, it's the fastest zk proving system in the market.）Thanks for your support to ZKSwap, we will open source the zk circuit code once the final audit is complete.
