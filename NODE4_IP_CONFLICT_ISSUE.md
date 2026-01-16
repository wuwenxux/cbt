# RBD Client Issue on node4

**Root Cause**: node4 had duplicate IP `10.103.11.244` (same as node2 OSD), causing network routing conflict that blocked RBD client from accessing OSD data.

**Fix**: 
```bash
sudo ip addr del 10.103.11.244/24 dev eth0
```
