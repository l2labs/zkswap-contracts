# ZKSwap-contracts

## ZKSwap protocal
ZKSwap is a layer2 AMM dex based on ethereum, using zkspeed protocal:
1. support AMM related transactions (create_pair, add_liquidity, remove_liquidity, swap)
2. support pair token creation/management and enabling pair token transfer between L2 and L1
3. enabling liquidity token exit if in exodus mode
4. enable commit blocks feature - more blocks can be committed in one transaction 
5. enable proof aggeration verification feature
the details are descirbed in the link:https://github.com/l2labs/zkswap-spec


## Reference
Smart contract audit report:
https://github.com/l2labs/zkswap-security-audit-certification


Great thanks to Matter Labs and zkSync team who made outstanding contributions to Layer2 ecosystem and ZK-Rollup technology. ZKSwap did a lot of work to add the swap circuit and also build a more efficiency Layer2 zk proving system （use more than 100 high performance servers and 200 piece 2080Ti  GPU Cards, and as far as we know, it's fastest  zk proving system in the market.）thanks for your support to ZKSwap, we will open the zk circuit code once the final audit finish.
