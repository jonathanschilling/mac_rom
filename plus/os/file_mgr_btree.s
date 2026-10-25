| File Manager - B-tree Engine
|
| Generic B-tree implementation used by HFS for both the catalog file
| and the extents overflow file. Supports search, insert, delete, and
| node splitting/rotation for balanced B*-trees.
|
| B-tree operations (via low-memory vector trampolines):
| BTOpen - open a B-tree file
| BTClose - close a B-tree file
| BTSearch - search for a key in the B-tree
| BTInsert - insert a new record
| BTDelete - delete a record
| BTUpdate - update an existing record
| BTFlush - flush B-tree nodes to disk
| BTGetRecord - get a record by index within a node
|
| Node management:
| GetNode/RelNode - get/release a B-tree node (via block cache)
| SearchNode - binary search within a node
| InsertRec - insert a record into a node
| DeleteRec - delete a record from a node
| RotateLT/SplitLT - rebalance via rotation or split
|
| References:
| Inside Macintosh: Files, Ch 2: "Data Organization on Volumes"
|

| ----------------------------------------------------------
|
| P_m BT Close
|
P_mBTClose:
        MOVE.L  (0x730).w,-(SP)                 | HFS vector: BTClose
        RTS                                     | return from P_mBTClose

| ----------------------------------------------------------
|
| BT Close
|
BTClose:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1-D4/A0-A4,-(A6)               | Save regs for BTClose
        MOVE    D0,D3                           | D3 = B-tree file refnum
        MOVE    D3,D0                           | D0 = refnum for LocBTCB lookup
        JSR     LocBTCB(PC)                     | Find BTCB for this B-tree file -> A4
        JSR     P_mBTFlush(PC)                  | Flush B-tree header (BTH) to disk node 0
        BNE.B   BTCLOSE_EXIT                    | BTFlush error?
        MOVE    D3,D0                           | D0 = refnum for cache flush
        MOVEQ.L #0x1,D1                         | D1 = kFCtrash: trash all cached B-tree blocks
        MOVE.L  BTCCQPtr(A4),A1                 | A1 = cache queue for this B-tree (from BTCB)
        JSR     P_mFlushCache(PC)               | Flush and invalidate all cached B-tree nodes
        BNE.B   BTCLOSE_EXIT                    | Cache flush error?
        MOVE.L  A4,A0                           | A0 = BTCB pointer (for deallocation)
        _DisposePtr                             | Free BTCB memory block
        MOVE.L  (FCBSPtr).w,A4                  | A4 = FCB array (to clear B-tree extension)
        CLR.L   0x22(A4,D3.W)                   | Clear FCB's BTCB extension pointer (B-tree no longer open)
        CLR     D0                              | D0 = noErr
BTCLOSE_EXIT:
        MOVEM.L (A6)+,D1-D4/A0-A4               | Restore registers
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | Set Z flag from result
        RTS                                     | return from BTCLOSE_EXIT

| P_mBTDelete -- delete the record.
| ----------------------------------------------------------
|
| P_m BT Delete
|
| Called by: DC_DELETE, DEALLOCFILE_NO_2, TRUNCATEFILE_OK, CC_CLR_THD_LOOP, MC_UPD_DEST (and 1 more)
P_mBTDelete:
        MOVE.L  (0x734).w,-(SP)                 | HFS vector: BTDelete
        RTS                                     | return from P_mBTDelete

| ----------------------------------------------------------
|
| BT Delete
|
BTDelete:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1-D5/A0-A4,-(A6)               | Save regs for BTDelete
        BSR     BT_SETUP                        | BT_SETUP: extract file refnum from key, find BTCB -> A4
        CLR.L   BTCNodeM(A4)                    | Clear BTCNodeM (no node mark from previous operation)
        SUBA.L  A2,A2                           | A2 = nil (no secondary node held)
        SUBA.L  A3,A3                           | A3 = nil (no primary node held yet)
        JSR     TreeSearch(PC)                  | TreeSearch: descend B-tree from root to leaf for this key
        MOVE.L  A1,A3                           | A3 = leaf node containing the key (from A1)
        BNE     BTDEL_CLEANUP                   | Key not found -> BTnotfound error
        MOVE    D1,D5                           | D5 = tree level of found record (1=leaf)
BTDEL_DELREC:
        MOVE.L  A3,A1                           | Delete the record from the current B-tree node
        MOVE    D5,D1                           | A3 used as A1 for DeleteRec call
        JSR     DeleteRec(PC)                   | DeleteRec: remove record at index D1 from node A3
        MOVE.L  A3,A0                           | A0 = node buffer (for MarkBlock)
        JSR     P_mMarkBlock(PC)                | Mark modified node as dirty in cache
        TST     D5                              | At root level? (D5=0 means we've reached the root)
        BNE     BTDEL_CHKLEAF                   | No: done at this level
        BSET    #0x6,(A4)                       | Set BTCKeyUpd flag: index key changed at root
BTDEL_CHKLEAF:
        CMPI.B  #0xFF,NDType(A3)                | Is this a leaf node? (NDType = 0xFF)
        BNE.B   BTDEL_CHKRECS                   | No: check key update
        SUBQ.L  #0x1,BTCNRecs(A4)               | Leaf deletion: decrement BTCNRecs (total leaf records)
BTDEL_CHKRECS:
        TST     NDNRecs(A3)                     | Any records remaining in this node?
        BGT     BTDEL_NXTLEV                    | Records remain: check if parent index key needs update
        MOVE.L  A3,A0                           | Node empty: must update sibling links before freeing
        JSR     GetLTSib(PC)                    | GetLTSib: get left sibling to update its forward link
        BNE     BTDEL_CLEANUP                   | Error getting sibling?
        TST.L   D1                              | D1 = left sibling node number (0 if none)
        BEQ.B   BTDEL_GETRSIB                   | No left sibling: skip link update
        MOVE.L  (A3),(A1)                       | Update left sibling's NDFLink to skip deleted node
        MOVEQ.L #0x4,D1                         | D1 = RBdirty: mark left sibling dirty after link update
        MOVE.L  A1,A0                           | A0 = left sibling for release
        JSR     P_mRelNode(PC)                  | Release left sibling node
BTDEL_GETRSIB:
        MOVE.L  A3,A0                           | Get right sibling to update its backward link
        JSR     GetRTSib(PC)                    | GetRTSib: get right sibling node
        BNE     BTDEL_CLEANUP                   | Delete index record from parent
        TST.L   D1                              | Has right sibling?
        BEQ.B   BTDEL_UPDPTRS                   | No right sibling: skip
        MOVE.L  NDBlink(A3),0x4(A1)             | Update right sibling's NDBlink to skip deleted node
        MOVEQ.L #0x4,D1                         | D1 = RBdirty
        MOVE.L  A1,A0                           | A0 = right sibling
        JSR     P_mRelNode(PC)                  | Release right sibling
| BDUpdPtrs: update 1st and last node pointers
BTDEL_UPDPTRS:
        CMPI.B  #0xFF,NDType(A3)                | at leaf level? (NDLeafNode = $FF)
        BNE.B   BTDEL_FREENODE                  | no ->
        TST.L   NDBlink(A3)                     | backward link = 0?
        BNE.B   BTDEL_CHKFLINK                  | no ->
        MOVE.L  (A3),BTCFNode(A4)               | yes, update 1st node number
BTDEL_CHKFLINK:
        TST.L   (A3)                            | forward link = 0?
        BNE.B   BTDEL_FREENODE                  | no ->
        MOVE.L  NDBlink(A3),BTCLNode(A4)        | yes, update last node number
| BDFree: free the empty node
BTDEL_FREENODE:
        MOVE.L  A3,A0                           | clear the empty node
        JSR     ClrNode(PC)                     | zero out the node buffer
        MOVEQ.L #0x4,D1                         | release dirty
        JSR     P_mRelNode(PC)                  | release node buffer
        SUBA.L  A3,A3                           | indicate no buffer
        MOVE    BTCLevel(A4),D0                 | locate
        JSR     LocTPR(PC)                      | TPR for current level
        MOVE.L  (A0),D1                         | free
        MOVE    BTCRefNum(A4),D0                | B-tree file refnum
        JSR     P_mFreeNode(PC)                 | the disk node
        BSET    #0x4,(A4)                       | indicate index record delete (BTCDelIRec)
        BCLR    #0x6,(A4)                       | and no key update (BTCKeyUpd)
| BDNxtLev: move to next level up
BTDEL_NXTLEV:
        SUBQ.W  #0x1,BTCLevel(A4)               | bump to next level up
        BEQ     BTDEL_ROOT                      | up to root level ->
        BTST    #0x6,(A4)                       | key update required? (BTCKeyUpd)
        BNE.B   BTDEL_GETPAR                    | yes ->
        BTST    #0x4,(A4)                       | index record delete required? (BTCDelIRec)
        BEQ     BTDEL_DONE                      | no, all done ->
BTDEL_GETPAR:
        MOVE    BTCLevel(A4),D0                 | locate TPR
        JSR     LocTPR(PC)                      | for this level
        MOVE    0x4(A0),D5                      | D5 = parent record index (TPRRIndx)
        MOVE.L  (A0),D2                         | D2 = parent node number (TPRNodeN)
        MOVEQ.L #0x0,D1                         | get parent node
        JSR     P_mGetNode(PC)                  | read parent node into cache
        MOVE.L  A0,A2                           | A2 = ptr(parent node buffer)
| BDUpdKey: update parent key
        BTST    #0x6,(A4)                       | key update required? (BTCKeyUpd)
        BEQ.B   BTDEL_RELCHILD                  | no ->
        MOVE    D5,D0                           | locate
        MOVE.L  A2,A1                           | A1 = parent node buffer
        JSR     GetRecA(PC)                     | parent index record
        MOVE.L  A0,-(SP)                        | and save it
        MOVE.L  A3,A1                           | locate 1st key
        CLR     D0                              | record index 0 (first record)
        JSR     GetRecA(PC)                     | in node
        MOVE.L  (SP)+,A1                        | ptr(parent index record)
        JSR     UpdIKey(PC)                     | update the key
        MOVE.L  A2,A0                           | ptr(parent node buffer)
        JSR     P_mMarkBlock(PC)                | mark it dirty
        TST     D5                              | update to 1st key in node?
        BEQ.B   BTDEL_RELCHILD                  | yes, leave flag set ->
        BCLR    #0x6,(A4)                       | don't need to update next level
BTDEL_RELCHILD:
        MOVEQ.L #0x0,D1                         | release child
        MOVE.L  A3,A0                           | A0 = child node buffer
        JSR     P_mRelNode(PC)                  | node buffer
        MOVE.L  A2,A3                           | new child node = parent node
        MOVE    D2,D3                           | should be a long, not word (Sys7 bug note)
| check if done
        BCLR    #0x4,(A4)                       | index rec delete required? (BTCDelIRec)
        BEQ.B   BTDEL_CHKUPD                    | no ->
        BRA     BTDEL_DELREC                    | delete parent index record ->

| ----------------------------------------------------------
|
| BTDEL_CHKUPD
|
BTDEL_CHKUPD:
        BTst    #0x6,(A4)                       | another key update required? (BTCKeyUpd)
        BNE.B   BTDEL_NXTLEV                    | yes ->
        BRA.B   BTDEL_DONE                      | no, all done ->

| ----------------------------------------------------------
|
| BTDEL_ROOT - BDRoot: up to root, check for empty tree
|
BTDEL_ROOT:
        MOVE.L  A3,D0                           | root node released?
        BNE.B   BTDEL_UPDDEPTH                  | no ->
        CLR     BTCDepth(A4)                    | set tree to empty state
        CLR.L   BTCRoot(A4)                     | no root node
        BRA.B   BTDEL_DONE                      | exit ->

| ----------------------------------------------------------
|
| BTDEL_UPDDEPTH
|
| BDUpdDepth: update tree depth if root has only 1 index record
BTDEL_UPDDEPTH:
        CMPI    #0x1,NDNRecs(A3)                | check # of records left in root
        BGT     BTDEL_DONE                      | > 1, all done ->
        TST.B   NDType(A3)                      | index node? (NDType = 0 for index)
        BNE     BTDEL_DONE                      | no, all done ->
        SUBQ.W  #0x1,BTCDepth(A4)               | decrement tree depth
        MOVEQ.L #0x0,D1                         | locate key and data for 1st record
        MOVE.L  A3,A1                           | A1 = root node buffer
        JSR     LocRec(PC)                      | in node
        MOVE.L  (A1),BTCRoot(A4)                | new root = child node
| release the previous root node
        MOVE.L  A3,A0                           | clear the node buffer
        JSR     ClrNode(PC)                     | zero out the node
        MOVEQ.L #0x4,D1                         | release the
        JSR     P_mRelNode(PC)                  | node buffer (dirty)
        SUBA.L  A3,A3                           | indicate no buffer
        MOVE.L  D3,D1                           | free
        MOVE    BTCRefNum(A4),D0                | B-tree file refnum
        JSR     P_mFreeNode(PC)                 | the node
| BDExit: release last node and exit
BTDEL_DONE:
        BSet    #0x7,(A4)                       | mark BTCB dirty (BTCDirty)
        CLR     D0                              | result = ok
BTDEL_CLEANUP:
        MOVE    D0,-(A6)                        | save result code
        MOVE.L  A3,A0                           | ptr(node buffer)
        MOVEQ.L #0x0,D1                         | release without write
        JSR     P_mRelNode(PC)                  | release it
        MOVE    (A6)+,D0                        | restore result code
        BSR     BT_CLEANUP                      | BTCleanUp
        MOVEM.L (A6)+,D1-D5/A0-A4               | restore regs
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit BTDelete

| P_mBTFlush -- flush B-tree header (BTH) to disk node 0.
| ----------------------------------------------------------
|
| P_m BT Flush
|
P_mBTFlush:
        MOVE.L  (0x738).w,-(SP)                 | HFS vector: BTFlush
        RTS                                     | return from P_mBTFlush

| ----------------------------------------------------------
|
| BT Flush
|
BTFlush:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1-D4/A0-A4,-(A6)               | save regs
        MOVE    D0,D3                           | D3 = file refnum
        MOVE.L  (FCBSPtr).w,A1                  | point into FCB array
        MOVE.L  0x14(A1,D3.W),A2                | point to VCB
        TST     vcbDrvNum(A2)                   | volume offline?
        BEQ.B   BTFLUSH_EXIT                    | yes, nothing could have changed ->
        JSR     LocBTCB(PC)                     | locate the BTCB
        BCLR    #0x7,(A4)                       | is the BTCB dirty? (BTCDirty)
        BEQ.B   BTFLUSH_CACHE                   | no, just flush cache ->
| get BTH from disk
        MOVEQ.L #0x0,D1                         | no options
        MOVEQ.L #0x0,D2                         | BTH is disk block 0
        JSR     P_mGetNode(PC)                  | get disk block
        BNE.B   BTFLUSH_EXIT                    | couldn't get it ->
        MOVE.L  A0,A3                           | A3 = cache buffer ptr
| update BTH from BTCB info
        MOVE    #0x1D,D0                        | loop index = LenMemBTH-1 (30-1=29=$1D)
        LEA.L   BTCDepth(A4),A0                 | ptr(source) = BTCB header fields
        LEA.L   NDResv2+2(A3),A1                | ptr(destination) = BTH in node (after ND)
BTFLUSH_CPYLOOP:
        MOVE.B  (A0)+,(A1)+                     | move it
        DBF     D0,BTFLUSH_CPYLOOP              | in
| release cache buffer
        MOVEQ.L #0x4,D1                         | release 'dirty'
        MOVE.L  A3,A0                           | cache buffer ptr
        JSR     P_mRelNode(PC)                  | release it
        BNE.B   BTFLUSH_EXIT                    | error ->
| BFFlush: flush the cache for this file
BTFLUSH_CACHE:
        MOVE    D3,D0                           | file refnum
        MOVEQ.L #0x0,D1                         | no FlushCache options
        MOVE.L  BTCCQPtr(A4),A1                 | cache queue ptr
        JSR     P_mFlushCache(PC)               | flush it
        NOP                                     | (was: BNE.S BFExit, patched out)
| BFExit
BTFLUSH_EXIT:
        MOVEM.L (A6)+,D1-D4/A0-A4               | restore regs
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit BTFlush

| P_mBTGetRecord -- get next catalog record.
| ----------------------------------------------------------
|
| P_m BT Get Record
|
P_mBTGetRecord:
        MOVE.L  (0x73C).w,-(SP)                 | HFS vector: BTGetRecord
        RTS                                     | return from P_mBTGetRecord

| ----------------------------------------------------------
|
| BT Get Record
|
BTGetRecord:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D3-D5/A2-A4,-(A6)               | save regs
        BSR     BT_SETUP                        | BTSetUp: set up common stuff
        MOVE    D1,D5                           | D5 = selection code
        SUBA.L  A3,A3                           | indicate no node buffer
        MOVE    BTCIndexM(A4),D4                | current index mark
        MOVE.L  BTCNodeM(A4),D3                 | current node mark
        BNE.B   BTREC_LOCATE                    | valid node number ->
        MOVEQ.L #0x20,D0                        | result = BTnotfound
        BRA.B   BTREC_EXIT                      | exit ->

| ----------------------------------------------------------
|
| BTREC_LOCATE - GRLocate: locate record relative to starting position
|
BTREC_LOCATE:
        ADD     D5,D4                           | adjust index by selection code
BTREC_GETNODE:
        BSR     GR_GETNODE                      | GRGetNode: release current, get next
        BNE.B   BTREC_EXIT                      | error ->
BTREC_CHKINDX:
        TST     D4                              | check index bounds
        BLT.B   BTREC_GETPREV                   | < 0, get previous node ->
        MOVE    NDNRecs(A3),D1                  | D1 = number of records in node
        CMP     D1,D4                           | index within this node?
        BLT.B   BTREC_FOUND                     | < #recs, got it ->
        MOVE.L  (A3),D0                         | get next node number (NDFlink)
        BEQ.B   BTREC_ATEND                     | don't have one ->
        MOVE.L  D0,D3                           | D3 = next node number
        SUB     D1,D4                           | adjust index
        BRA.B   BTREC_GETNODE                   | try next node

| ----------------------------------------------------------
|
| BTREC_ATEND - at end of leaf chain, use last record as mark
|
BTREC_ATEND:
        MOVE    D1,D4                           | new index mark = index of last record
        SUBQ.W  #0x1,D4                         | adjust to 0-based index
        BRA.B   BTREC_SETMARK                   | use common exit ->

| ----------------------------------------------------------
|
| BTREC_GETPREV - get previous node
|
BTREC_GETPREV:
        MOVE.L  NDBlink(A3),D0                  | get previous node number
        BEQ.B   BTREC_ATBEGIN                   | don't have one ->
        MOVE.L  D0,D3                           | D3 = previous node number
        BSR     GR_GETNODE                      | GRGetNode: get the previous node
        BNE.B   BTREC_EXIT                      | error ->
        ADD     NDNRecs(A3),D4                  | adjust index
        BRA.B   BTREC_CHKINDX                   | check bounds again ->

| ----------------------------------------------------------
|
| BTREC_ATBEGIN - at beginning of leaf chain
|
BTREC_ATBEGIN:
        MOVEQ.L #0x0,D4                         | new index mark = index of first record
BTREC_SETMARK:
        MOVE.L  D3,BTCNodeM(A4)                 | new node mark
        MOVE    D4,BTCIndexM(A4)                | new index mark
        MOVEQ.L #0x20,D0                        | result = BTnotfound
        BRA     BTREC_EXIT                      | exit ->

| ----------------------------------------------------------
|
| BTREC_FOUND - GRGotIt: found the record
|
BTREC_FOUND:
        MOVE    D4,D1                           | record index
        MOVE.L  A3,A1                           | ptr(node buffer)
        JSR     LocRec(PC)                      | locate key and data record
        MOVE.L  D3,BTCNodeM(A4)                 | update current node
        MOVE    D4,BTCIndexM(A4)                | and index markers
| GRExit
        CLR     D0                              | result = ok
BTREC_EXIT:
        MOVEM.L D0-D1/A0-A1,-(A6)               | save return stuff
        BSR     GR_RELNODE                      | GRRelNode: release node buffer
        MOVEM.L (A6)+,D0-D1/A0-A1               | restore return stuff
        MOVE.L  D3,D2                           | hint = node number
        BSR     BT_CLEANUP                      | BTCleanUp
        MOVEM.L (A6)+,D3-D5/A2-A4               | restore regs
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit BTGetRecord

| ----------------------------------------------------------
|
| GR_GETNODE - GRGetNode: releases current node and gets next
|
GR_GETNODE:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        BSR     GR_RELNODE                      | release current node
        MOVEQ.L #0x0,D1                         | no GetBlock options
        MOVE.L  D3,D2                           | node number
        JSR     P_mGetNode(PC)                  | get the node
        BNE.B   GRGETNODE_EXIT                  | error ->
        MOVE.L  A0,A3                           | A3 = ptr(next node buffer)
GRGETNODE_EXIT:
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit GRGetNode

| ----------------------------------------------------------
|
| GR_RELNODE - GRRelNode: releases current node buffer
|
GR_RELNODE:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEQ.L #0x0,D1                         | no RelBlock options
        MOVE.L  A3,A0                           | ptr(node buffer)
        JSR     P_mRelNode(PC)                  | release the node
        SUBA.L  A3,A3                           | indicate no node buffer
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit GRRelNode

| P_mBTInsert -- insert the record.
| ----------------------------------------------------------
|
| P_m BT Insert
|
| Called by: EXTENDFILE_LOOP, CC_ADD_REC, CC_CLR_THD_LOOP, MC_INSERT_DST, CMRenameCN
P_mBTInsert:
        MOVE.L  (0x740).w,-(SP)                 | HFS vector: BTInsert
        RTS                                     | return from P_mBTInsert

| ----------------------------------------------------------
|
| BT Insert
|
BTInsert:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1/D3-D7/A0-A4,-(A6)            | save registers
        JSR     LocBTCB(PC)                     | locate BTCB
        MOVE.L  A1,D7                           | D7 = ptr(record)
        MOVE    D1,D6                           | D6 = size of record
        MOVE.L  A0,D5                           | D5 = ptr(key)
| make sure there is enough file space for worst case split
        MOVEQ.L #0x1,D3                         | required space (in nodes) =
        ADD     BTCDepth(A4),D3                 | tree depth + 1
        CMP.L   BTCFree(A4),D3                  | enough space?
        BLE.B   BTINS_INIT                      | yes ->
BTINS_EXTEND:
        JSR     P_mExtBTFile(PC)                | extend the file
        BNE     BTINS_EXIT                      | couldn't do it ->
        CMP.L   BTCFree(A4),D3                  | enough space now?
        BGT.B   BTINS_EXTEND                    | no ->
| BIInit: initialize some things
BTINS_INIT:
        MOVE    BTCRefNum(A4),D0                | set up common stuff
        BSR     BT_SETUP                        | BTSetUp
        MOVEM.L D6-D7,-(A6)                     | save input record size and ptr
        MOVEQ.L #0x0,D4                         | indicate no parent node buffer
        SUBA.L  A2,A2                           | no left node buffer
        SUBA.L  A3,A3                           | no right node buffer
        CLR.L   BTCNodeM(A4)                    | invalidate current node mark
| build BTree record: input key with junk data record
        MOVE.L  BTCVarPtr(A4),A1                | dest = record buffer
        LEA.L   0x30(A1),A1                     | BTVRecord offset
        MOVE.L  D5,A0                           | source = input key
        MOVEQ.L #0x0,D0                         | get key length
        MOVE.B  (A0),D0                         | D0 = key length byte
        ADDQ.L  #0x2,D0                         | include length byte
        LSR.L   #0x1,D0                         | round up to word boundary
        LSL.L   #0x1,D0                         | adjust to word boundary
        ADD     D0,D6                           | total size = key size + data size
        _BlockMove                              | move in the key
        ADDQ.W  #0x1,D6                         | adjust total size to word boundary
        LSR     #0x1,D6                         | divide by 2
        LSL     #0x1,D6                         | multiply by 2 (round to even)
        MOVE.L  A1,D7                           | D7 = ptr(BTree record)
| BISearch: search tree for key
        JSR     TreeSearch(PC)                  | search for key
        MOVE.L  A1,A3                           | A3 = ptr(right node buffer)
        BNE.B   BTINS_CHKERR                    | key not found or error ->
        MOVEQ.L #0x21,D0                        | error, it already exists (BTexists)
        BRA     BTINS_CLEANUP                   | exit ->

| ----------------------------------------------------------
|
| BTINS_CHKERR
|
BTINS_CHKERR:
        CMPI    #0x20,D0                        | key not found? (BTnotfound)
        BNE     BTINS_CLEANUP                   | no, must be IO error ->
        MOVE.L  D2,D3                           | D3 = right node number
        MOVE    D1,D5                           | D5 = insert index
| if tree is empty, add 1st leaf node
        TST     BTCLevel(A4)                    | tree empty?
        BGT     BTINS_INSERT                    | no ->
        MOVE    BTCRefNum(A4),D0                | file refnum
        JSR     P_mAllocNode(PC)                | allocate the node
        BNE     BTINS_CLEANUP                   | error ->
        MOVE.L  D1,D3                           | D3 = new node number
        JSR     InitNode(PC)                    | get an initialized node
        MOVE.L  A0,A3                           | A3 = ptr(new root node)
        MOVE.B  #0xFF,NDType(A3)                | type = leaf node (NDLeafNode = $FF)
        MOVEQ.L #0x1,D0                         | node height = 1
        MOVE.B  D0,NDNHeight(A3)                | set node height to 1
        MOVE    D0,BTCDepth(A4)                 | tree depth = 1
        MOVE.L  D3,BTCRoot(A4)                  | new root node number
        MOVE.L  D3,BTCFNode(A4)                 | 1st and last node pointers
        MOVE.L  D3,BTCLNode(A4)                 | last leaf = same (only node)
        MOVE    #0x1,BTCLevel(A4)               | current level = 1
| BIInsert: try a simple insert first
BTINS_INSERT:
        MOVE.L  D7,A0                           | ptr(record)
        MOVE    D6,D0                           | record size
        MOVE.L  A3,A1                           | ptr(node buffer)
        MOVE    D5,D1                           | insert index
        JSR     InsertRec(PC)                   | try to insert it
        BNE.B   BTINS_ROTATE                    | didn't make it ->
        TST     D5                              | insert a new 1st record?
        BNE.B   BTINS_INSDONE                   | no, insert complete ->
        BSET    #0x6,(A4)                       | indicate key update required (BTCKeyUpd)
        BRA.B   BTINS_INSDONE                   | insert complete ->

| ----------------------------------------------------------
|
| BTINS_ROTATE - BIRotate: try rotation into left sibling
|
BTINS_ROTATE:
        MOVE.L  A3,A0                           | ptr(node buffer)
        JSR     GetLTSib(PC)                    | get left sibling node
        BNE     BTINS_CLEANUP                   | error ->
        TST.L   D1                              | is there a left sibling?
        BEQ.B   BTINS_SPLIT                     | no ->
        MOVE.L  D1,D2                           | D2 = left node number
        MOVE.L  A1,A2                           | A2 = ptr(left node buffer)
        MOVE.L  D7,A0                           | ptr(record)
        MOVE    D6,D0                           | record size
        MOVE    D5,D1                           | insert index
        JSR     RotateLT(PC)                    | try rotating left
        BNE.B   BTINS_SPLIT                     | didn't make it ->
        BRA.B   BTINS_KEYUPD                    | use common code ->

| ----------------------------------------------------------
|
| BTINS_SPLIT - BISplit: rotate didn't work, got to split
|
BTINS_SPLIT:
        MOVE.L  D7,A0                           | ptr(record)
        MOVE    D6,D0                           | record size
        MOVE    D5,D1                           | insert index
        JSR     SplitLT(PC)                     | split left
        BEQ.B   BTINS_NEWIREC                   | ok ->
        MOVEQ.L #0x23,D0                        | result = 'no fit' (BTnoFit)
        BRA     BTINS_CLEANUP                   | exit ->

| ----------------------------------------------------------
|
| BTINS_NEWIREC - BISplit1: new index record required after split
|
BTINS_NEWIREC:
        BSet    #0x5,(A4)                       | indicate new index record required (BTCNewIRec)
BTINS_KEYUPD:
        BSet    #0x6,(A4)                       | indicate key update required (BTCKeyUpd)
        MOVE    D1,D5                           | D5 = new record index
        MOVE.L  A2,A0                           | mark the left node dirty
        JSR     P_mMarkBlock(PC)                | mark left node buffer dirty
| BIInsDone: completed the record insert
BTINS_INSDONE:
        MOVE.L  A3,A0                           | mark the right node dirty
        JSR     P_mMarkBlock(PC)                | mark right node buffer dirty
        CMPI.B  #0xFF,0x8(A1)                   | leaf level? (NDLeafNode)
        BNE.B   BTINS_CKDONE                    | no ->
        MOVEM.L (A6),D0/A0                      | get input record ptr and size
        JSR     UpdDRec(PC)                     | replace the junk data record
        ADDQ.L  #0x1,BTCNRecs(A4)               | bump leaf record count
        MOVE    D5,BTCIndexM(A4)                | save index marker
        MOVE.L  D3,D0                           | assume right node number
        CMPA.L  A3,A1                           | is new record in right node?
        BEQ.B   BTINS_SAVEMARK                  | yes ->
        MOVE.L  D2,D0                           | no, use left node number
BTINS_SAVEMARK:
        MOVE.L  D0,BTCNodeM(A4)                 | save node marker
| BICkDone: check if all done
BTINS_CKDONE:
        BTst    #0x6,(A4)                       | key update required? (BTCKeyUpd)
        BNE.B   BTINS_NXTLEV                    | yes, move to next level ->
        BTST    #0x5,(A4)                       | new index record required? (BTCNewIRec)
        BEQ     BTINS_DONE                      | no, all done ->
| BINxtLev: move to next level
BTINS_NXTLEV:
        SUBQ.W  #0x1,BTCLevel(A4)               | bump to next level up
        BEQ     BTINS_NEWROOT                   | up to root level ->
        MOVE    BTCLevel(A4),D0                 | locate TPR
        JSR     LocTPR(PC)                      | for this level
        MOVE    0x4(A0),D5                      | D5 = parent record index
        MOVE.L  (A0),D3                         | D3 = parent node number
        MOVE.L  D2,-(A6)                        | save D2
        MOVEQ.L #0x0,D1                         | get parent node
        MOVE.L  D3,D2                           | D2 = parent node number
        JSR     P_mGetNode(PC)                  | read parent node into cache
        BNE     BTINS_CLEANUP                   | error ->
        MOVE.L  A0,D4                           | D4 = ptr(parent node buffer)
        MOVE.L  (A6)+,D2                        | restore D2
| BIUpdKey: update parent key
        BTST    #0x6,(A4)                       | key update required? (BTCKeyUpd)
        BEQ.B   BTINS_RELRIGHT                  | no ->
        MOVE    D5,D0                           | locate
        MOVE.L  D4,A1                           | A1 = parent node buffer
        JSR     GetRecA(PC)                     | parent index record
        MOVE.L  A0,-(SP)                        | and save it
        MOVE.L  A3,A1                           | locate 1st key
        CLR     D0                              | record index 0
        JSR     GetRecA(PC)                     | in right node
        MOVE.L  (SP)+,A1                        | ptr(parent index record)
        JSR     UpdIKey(PC)                     | update the key
        MOVE.L  D4,A0                           | mark the parent node dirty
        JSR     P_mMarkBlock(PC)                | mark parent dirty
        TST     D5                              | update to 1st key in node?
        BEQ.B   BTINS_RELRIGHT                  | yes, leave flag set ->
        BCLR    #0x6,(A4)                       | don't need to update next level
BTINS_RELRIGHT:
        MOVEQ.L #0x0,D1                         | release
        MOVE.L  A3,A0                           | A0 = right node buffer
        JSR     P_mRelNode(PC)                  | right node buffer
        MOVE.L  D4,A3                           | parent is new right node
        MOVEQ.L #0x0,D4                         | indicate no parent node buffer
| BINewRec: build new index record pointing at new left node
        BTST    #0x5,(A4)                       | new index record required? (BTCNewIRec)
        BEQ.B   BTINS_RELLEFT                   | no ->
        MOVE.L  A2,A1                           | left node
        MOVE.L  D2,D0                           | left node number
        JSR     BuildIRec(PC)                   | build index record
BTINS_RELLEFT:
        MOVEQ.L #0x0,D1                         | release
        MOVE.L  A2,A0                           | A0 = left node buffer
        JSR     P_mRelNode(PC)                  | left node buffer
        SUBA.L  A2,A2                           | indicate no left node
| set up for insert of new index record
        BTST    #0x5,(A4)                       | new index record required? (BTCNewIRec)
        BEQ     BTINS_CKDONE                    | no, check if done ->
        MOVE.L  BTCVarPtr(A4),A0                | locate new index record
        LEA.L   0x30(A0),A0                     | A0 = BTVRecord (record buffer, BTVars+$30)
        MOVE.L  A0,D7                           | D7 = ptr to new record
        JSR     GetMaxKey(PC)                   | max key length + 4
        ADDQ.W  #0x4,D0                         | = size of index record
        MOVE    D0,D6                           | D6 = size of new record
        BCLR    #0x5,(A4)                       | clear new index rec flag
        BRA     BTINS_INSERT                    | insert new index record ->

| ----------------------------------------------------------
|
| BTINS_NEWROOT
|
BTINS_NEWROOT:
        BTst    #0x5,(A4)                       | Test bit
        BEQ     BTINS_DONE                      | yes ->
        MOVE    BTCRefNum(A4),D0                | D0 = file refnum for AllocNode
        JSR     P_mAllocNode(PC)                | AllocNode: allocate a fresh B-tree node on disk
        BNE     BTINS_CLEANUP                   | Allocation failed?
        MOVE.L  D1,D3                           | D3 = new node number
        MOVE.L  D3,D1                           | D1 = node number for InitNode
        JSR     InitNode(PC)                    | InitNode: initialize node descriptor (type, height, zero records)
        MOVE.L  A0,D4                           | D4 = node data pointer (save for later)
        CLR.B   0x8(A0)                         | NDType = 0 (index node, not leaf)
        MOVEQ.L #0x1,D0                         | D0 = current depth + 1 (new root is one level higher)
        ADD     BTCDepth(A4),D0                 | Add current depth
        MOVE.B  D0,0x9(A0)                      | NDNHeight = new root height
        MOVE.L  A2,A1                           | A1 = left child node (A2)
        MOVE.L  D2,D0                           | D0 = left child's node number (D2)
        JSR     BuildIRec(PC)                   | BuildIRec: build index record pointing to left child
        JSR     GetMaxKey(PC)                   | GetMaxKey: get highest key from left child
        ADDQ.W  #0x4,D0                         | D0 += 4 (key length + node number)
        MOVE.L  BTCVarPtr(A4),A0                | A0 = B-tree variables area
        LEA.L   0x30(A0),A0                     | A0 = BTVRecord (record buffer, BTVars+$30)
        MOVE.L  D4,A1                           | A1 = new root node data
        CLR     D1                              | D1 = 0 (insert at position 0)
        JSR     InsertRec(PC)                   | InsertRec: insert left child's index record into new root at pos 0
        MOVE    #0x1,D0                         | D0 = 1 (second record position)
        JSR     LocTPR(PC)                      | Get TPR for level 1
        MOVE.L  (A0),D0                         | D0 = right child node number
        MOVE.L  A3,A1                           | A1 = right child node (A3)
        JSR     BuildIRec(PC)                   | BuildIRec: build index record pointing to right child
        JSR     GetMaxKey(PC)                   | GetMaxKey: get highest key from right child
        ADDQ.W  #0x4,D0                         | D0 += 4
        MOVE.L  BTCVarPtr(A4),A0                | A0 = record buffer
        LEA.L   0x30(A0),A0                     | A0 = BTVRecord (record buffer, BTVars+$30)
        MOVE.L  D4,A1                           | A1 = root node data
        MOVE    #0x1,D1                         | D1 = 1 (insert at position 1)
        JSR     InsertRec(PC)                   | InsertRec: insert right child's index record at pos 1
        MOVE.L  D4,A0                           | A0 = root node data (for marking)
        JSR     P_mMarkBlock(PC)                | MarkBlock: mark new root node dirty
        ADDQ.W  #0x1,BTCDepth(A4)               | Increment BTCDepth (tree grew one level)
        MOVE.L  D3,BTCRoot(A4)                  | BTCRoot = new root node number
BTINS_DONE:
        BSet    #0x7,(A4)                       | Set BTCDirty: B-tree header changed
        CLR     D0                              | D0 = noErr
BTINS_CLEANUP:
        MOVE    D0,-(A6)                        | Save result on A6 stack
        MOVE.L  A2,A0                           | A0 = left child (for release)
        MOVEQ.L #0x0,D1                         | D1 = 0 (no special release flags)
        JSR     P_mRelNode(PC)                  | Release left child node
        MOVE.L  A3,A0                           | A0 = right child
        JSR     P_mRelNode(PC)                  | Release right child node
        MOVE.L  D4,A0                           | A0 = root node
        JSR     P_mRelNode(PC)                  | Release root node
        MOVE    (A6)+,D0                        | Restore result
        MOVE.L  BTCNodeM(A4),D2                 | D2 = saved node mark
        CLR.L   BTCNodeM(A4)                    | Clear node mark
        BSR     BT_CLEANUP                      | Restore from node mark (BT_CLEANUP)
        ADDQ.L  #0x8,A6                         | Skip saved D2 + padding on A6 stack
BTINS_EXIT:
        MOVEM.L (A6)+,D1/D3-D7/A0-A4            | Restore all registers
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | Set Z flag from result
        RTS                                     | return from BTINS_EXIT

| P_mBTOpen -- bTOpen: open the B*-Tree file.
| ----------------------------------------------------------
|
| P_m BT Open
|
P_mBTOpen:
        MOVE.L  (0x744).w,-(SP)                 | HFS vector: BTOpen
        RTS                                     | return from P_mBTOpen

| ----------------------------------------------------------
|
| BT Open
|
BTOpen:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1-D5/A0-A4,-(A6)               | save regs
        MOVE    D0,D3                           | D3 = file refnum
        MOVE.L  A0,D4                           | D4 = ptr(key compare routine)
        MOVE.L  A1,D5                           | D5 = cache queue ptr
| allocate and initialize a BTCB
        MOVEQ.L #0x36,D0                        | allocate space for BTCB (lenBTCB = 54)
        _NewPtrSysClear                         | allocate zeroed system heap block
        BNE     BTOPEN_EXIT                     | couldn't get it ->
        MOVE.L  A0,A4                           | A4 = BTCB ptr
        MOVE.L  (FCBSPtr).w,A3                  | A3 = start of FCB array
        MOVE.L  A4,0x22(A3,D3.W)                | set BTCB ptr in FCB (FCBBTCBptr)
        MOVE    D3,BTCRefNum(A4)                | set refnum
        MOVE.L  D4,BTCKeyCR(A4)                 | set ptr(key compare routine)
        MOVE.L  D5,BTCCQPtr(A4)                 | set ptr to cache queue
| get BTH from disk
        MOVE    D3,D0                           | file refnum
        MOVE.L  D5,A1                           | cache queue ptr
        MOVEQ.L #0x0,D1                         | no GetBlock options
        MOVEQ.L #0x0,D2                         | BTH is block 0
        JSR     P_mGetBlock(PC)                 | get the block
        BNE.B   BTOPEN_EXIT                     | couldn't get it ->
        MOVE.L  A0,A2                           | A2 = cache buffer ptr
| BOChkHdr: make sure the BTree header node is ok
        LEA.L   0xE(A2),A0                      | A0 = ptr to BTH (after node descriptor, lenND = 14)
        MOVE    BTHNodeSize(A0),D0              | node size (BTHNodeSize)
        BEQ.B   BTOPEN_BADHDR                   | node size = 0, error ->
        MOVE    D0,D1                           | check if multiple of 512
        ANDI    #0x1FF,D1                       | mask to low 9 bits
        BNE.B   BTOPEN_BADHDR                   | node size not 512 multiple, error ->
        MOVE.L  0xC(A3,D3.W),D2                 | physical length (FCBPLen)
        DIVU    D0,D2                           | physical length / node size
        SWAP    D2                              | = # of nodes
        CLR     D2                              | clear remainder
        SWAP    D2                              | D2 = quotient (node count)
        CMP.L   BTHNNodes(A0),D2                | same # as in BTH (BTHNNodes)?
        BNE.B   BTOPEN_BADHDR                   | no, error ->
        CMP.L   0x1A(A0),D2                     | free count < # of nodes (BTHFree)?
        BCS     BTOPEN_BADHDR                   | no, error ->
        SUBQ.L  #0x1,D2                         | D2 = max node #
        CMPI.B  #0x8,(A0)                       | tree depth <= max? (BTMaxDepth=8)
        BHI.B   BTOPEN_BADHDR                   | no, error ->
        CMP.L   0x2(A0),D2                      | root node # <= max? (BTHRoot)
        BCS     BTOPEN_BADHDR                   | no, error ->
        CMP.L   0xA(A0),D2                      | 1st leaf node # <= max? (BTHFNode)
        BCS     BTOPEN_BADHDR                   | no, error ->
        CMP.L   0xE(A0),D2                      | last node # <= max? (BTHLNode)
        BCC     BTOPEN_CPYBTH                   | yes ->
| BOBadHdr
BTOPEN_BADHDR:
        MOVEQ.L #0x25,D0                        | result = 'bad header node' (BTBadHdr)
        BRA.B   BTOPEN_RELBLK                   | ->

| ----------------------------------------------------------
|
| BTOPEN_CPYBTH
|
| BOCpyBTH: copy BTH into BTCB
BTOPEN_CPYBTH:
        MOVE    #0x1D,D0                        | loop index = LenMemBTH-1
        LEA.L   0xE(A2),A0                      | ptr(source) = BTH (node + lenND)
        LEA.L   BTCDepth(A4),A1                 | ptr(dest) = BTCB
BTOPEN_CPYLOOP:
        MOVE.B  (A0)+,(A1)+                     | move it
        DBF     D0,BTOPEN_CPYLOOP               | in
        CLR     D0                              | result = 'ok'
| BOExit: release header block and exit
BTOPEN_RELBLK:
        MOVE    D0,-(A6)                        | save result code
        MOVE.L  D5,A1                           | cache queue ptr
        MOVEQ.L #0x0,D1                         | release 'clean'
        MOVE.L  A2,A0                           | cache buffer ptr
        JSR     P_mRelBlock(PC)                 | release it
        BEQ.B   BTOPEN_RESULT                   | ok ->
        MOVE    D0,(A6)                         | replace previous result code
BTOPEN_RESULT:
        MOVE    (A6)+,D0                        | restore result code
BTOPEN_EXIT:
        MOVEM.L (A6)+,D1-D5/A0-A4               | restore regs
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit BTOpen

| P_mBTSearch -- find the record.
| ----------------------------------------------------------
|
| P_m BT Search
|
| Called by: MOUNTVOL_OK_9, DEALLOCFILE_NEXT, TRUNCATEFILE_NEXT, XFSearch, XFSEARCH_NO_2 (and 1 more)
P_mBTSearch:
        MOVE.L  (0x748).w,-(SP)                 | HFS vector: BTSearch
        RTS                                     | return from P_mBTSearch

| ----------------------------------------------------------
|
| BT Search
|
BTSearch:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D3-D7/A2-A4,-(A6)               | save regs
| initialize some things
        BSR     BT_SETUP                        | BTSetUp: set up common stuff
        MOVE.L  A0,A3                           | A3 = ptr to key
        SUBA.L  A2,A2                           | indicate no node buffer
| go directly to the leaf node if hint is given
        TST.L   D2                              | hint given?
        BEQ.B   BTSRCH_TREE                     | no, do tree search ->
        MOVEQ.L #0x0,D1                         | get target node
        JSR     P_mGetNode(PC)                  | read hint node into cache
        BNE.B   BTSRCH_RELNODE                  | error ->
        MOVE.L  A0,A2                           | A2 = ptr(node buffer)
        CMPI.B  #0xFF,0x8(A0)                   | leaf node? (NDLeafNode)
        BNE.B   BTSRCH_RELHINT                  | no ->
        TST     0xA(A0)                         | node empty? (NDNRecs)
        BLE.B   BTSRCH_RELHINT                  | yes ->
        MOVE.L  A3,A0                           | search node for key
        MOVE.L  A2,A1                           | A1 = node buffer
        JSR     SearchNode(PC)                  | binary search within node
        BEQ.B   BTSRCH_FOUND                    | found it ->
BTSRCH_RELHINT:
        MOVE.L  A2,A0                           | release node buffer
        MOVEQ.L #0x0,D1                         | no RelBlock options
        JSR     P_mRelNode(PC)                  | release hint node buffer
        BNE.B   BTSRCH_RELNODE                  | error ->
| BSTSrch: search tree for key
BTSRCH_TREE:
        MOVE.L  A3,A0                           | ptr to key
        JSR     TreeSearch(PC)                  | search tree for key
        MOVE.L  A1,A2                           | A2 = ptr(node buffer)
        BEQ.B   BTSRCH_FOUND                    | key found ->
        CMPI    #0x20,D0                        | key not found error? (BTnotfound)
        BNE.B   BTSRCH_EXIT                     | no, must be IO error ->
BTSRCH_FOUND:
        MOVE    D1,D5                           | D5 = record index
        MOVE    D0,-(A6)                        | save search result
| update current markers in BTCB
        MOVE.L  D2,BTCNodeM(A4)                 | update current node mark
        MOVE    D5,BTCIndexM(A4)                | and record index mark
| set up pointers to key and data record
        TST     (A6)                            | record found?
        BNE.B   BTSRCH_RELNODE                  | no ->
        MOVE    D5,D0                           | record index
        MOVE.L  A2,A1                           | ptr(node buffer)
        JSR     LocRec(PC)                      | locate the record
| BSExit: release node buffer and exit
BTSRCH_RELNODE:
        MOVEM.L D1-D2/A0-A1,-(A6)               | save return stuff
        MOVE.L  A2,A0                           | ptr(node buffer)
        MOVEQ.L #0x0,D1                         | no RelBlock options
        JSR     P_mRelNode(PC)                  | release it
        MOVEM.L (A6)+,D1-D2/A0-A1               | restore return stuff
        MOVE    (A6)+,D0                        | restore search result
BTSRCH_EXIT:
        BSR     BT_CLEANUP                      | BTCleanUp
        MOVEM.L (A6)+,D3-D7/A2-A4               | restore regs
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit BTSearch

| P_mBTUpdate -- update the BTree record.
| ----------------------------------------------------------
|
| P_m BT Update
|
| Called by: MC_UPD_DEST, XFSEARCH_LOOP_3, CC_UPD_PAR, DC_UPD_PAR, MC_UPD_SRC (and 3 more)
P_mBTUpdate:
        MOVE.L  (0x74C).w,-(SP)                 | HFS vector: BTUpdate
        RTS                                     | Return via trampoline

| ----------------------------------------------------------
|
| BT Update
|
BTUpdate:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1/A0-A1/A4,-(A6)               | save regs
        JSR     LocBTCB(PC)                     | locate BTCB
        MOVEQ.L #0x2,D1                         | indicate existing cache block (GBexist)
        JSR     P_mGetNode(PC)                  | get the node
        BNE.B   BTUPD_EXIT                      | error ->
        MOVEQ.L #0x4,D1                         | indicate dirty buffer (RBdirty)
        JSR     P_mRelNode(PC)                  | release the node
        BNE.B   BTUPD_EXIT                      | error ->
        CLR     D0                              | indicate no error
BTUPD_EXIT:
        MOVEM.L (A6)+,D1/A0-A1/A4               | restore regs
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit BTUpdate

| ----------------------------------------------------------
|
| BT_CLEANUP
|
| BTCleanUp: cleans up after a BTree service call
BT_CLEANUP:
        MOVE.L  D0,-(SP)                        | save registers
        BSR.B   CAL_BTVARS                      | CalBTVars: calculate size of BTVars
        ADDA.L  D0,A6                           | remove BTVars from A6 stack
        CLR.L   BTCVarPtr(A4)                   | clear pointer in BTCB
        MOVE.L  (SP)+,D0                        | restore registers
        RTS                                     | exit BTCleanUp

| ----------------------------------------------------------
|
| BT_SETUP - BTSetUp: sets up for a BTree service call
|
BT_SETUP:
        MOVE.L  D0,-(SP)                        | save registers
        JSR     LocBTCB(PC)                     | locate the BTCB
        BSR.B   CAL_BTVARS                      | CalBTVars: calculate size of BTVars
        SUBA.L  D0,A6                           | allocate space on A6 stack
        MOVE.L  A6,BTCVarPtr(A4)                | save pointer in BTCB
        BCLR    #0x5,(A4)                       | clear status flags (BTCNewIRec)
        BCLR    #0x4,(A4)                       | (BTCDelIRec)
        BCLR    #0x6,(A4)                       | (BTCKeyUpd)
        MOVE.L  (SP)+,D0                        | restore registers
        RTS                                     | exit BTSetUp

| ----------------------------------------------------------
|
| CAL_BTVARS - CalBTVars: calculate size of BTVars
|
CAL_BTVARS:
        JSR     GetMaxKey(PC)                   | get max key size
        ADDI    #0x30,D0                        | size of BTVars = lenTPT + 4 (0x30 = 48)
        RTS                                     | exit CalBTVars

| P_mAllocNode -- allocate the node.
| ----------------------------------------------------------
|
| P_m Alloc Node
|
P_mAllocNode:
        MOVE.L  (0x758).w,-(SP)                 | HFS vector: AllocNode
        RTS                                     | return from P_mAllocNode

| ----------------------------------------------------------
|
| Alloc Node
|
AllocNode:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D2-D4/A2-A3,-(A6)               | save registers
        MOVEQ.L #0x0,D4                         | beg node # for current map record
        SUBA.L  A2,A2                           | start with map in header node
| ANGetMap: get next map record
ALLOC_GETMAP:
        BSR     GET_MAP                         | GetMap: get next map record
        BEQ.B   ALLOC_SEARCH                    | ok ->
        CMPI    #0x20,D0                        | map node not found? (BTnotfound)
        BNE.B   ALLOC_EXIT                      | no, some other error ->
        MOVEQ.L #0x22,D0                        | result = 'no space' (BTnospace)
        BRA.B   ALLOC_EXIT                      | exit ->
| ANSearch: search map record for a free node (zero bit)
ALLOC_SEARCH:
        MOVE    D1,D2                           | map record size
        LSR     #0x2,D2                         | in long words
        SUBQ.W  #0x1,D2                         | - 1 = loop index
        MOVE.L  A1,A0                           | start at beginning of the record
ALLOC_SCANLW:
        MOVE.L  (A0)+,D0                        | next map long word
        CMPI.L  #0xFFFFFFFF,D0                  | any free blocks?
        BNE.B   ALLOC_FOUNDLW                   | yes ->
        DBF     D2,ALLOC_SCANLW                 | continue search
        EXT.L   D1                              | map record size
        LSL.L   #0x3,D1                         | x 8 = # of nodes
        ADD.L   D1,D4                           | adjust beg node #
        BRA.B   ALLOC_GETMAP                    | try next map record ->
| ANFound: found a long word with free blocks, locate 1st one
ALLOC_FOUNDLW:
        MOVE    #0x1F,D2                        | initial bit index
ALLOC_SCANBIT:
        BTst    D2,D0                           | free block?
        BEQ.B   ALLOC_FOUNDBIT                  | yes ->
        DBF     D2,ALLOC_SCANBIT                | try next bit
ALLOC_FOUNDBIT:
        BSet    D2,D0                           | mark block allocated
        MOVE.L  D0,D3                           | save updated map long word
        LEA.L   -0x4(A0),A0                     | position back to map long word
        MOVE.L  A0,A3                           | save ptr(map long word)
| calculate node number for the selected node
        SUBA.L  A1,A0                           | byte offset to word
        MOVE.L  A0,D1                           | put in D1
        LSL.L   #0x3,D1                         | x 8 = bit offset to long word
        ADDI.L  #0x1F,D1                        | + bit offset within long word
        EXT.L   D2                              | sign-extend bit index to long
        SUB.L   D2,D1                           | subtract bit position
        ADD.L   D4,D1                           | = node number
| check for end of map
        MOVE.L  BTCNNodes(A4),D0                | # of nodes = max node # + 1
        CMP.L   D1,D0                           | target node within map range?
        BGT.B   ALLOC_COMMIT                    | yes ->
        BSR     REL_MAP                         | RelMap: release map node
        MOVEQ.L #0x22,D0                        | result = 'no space' (BTnospace)
        BRA.B   ALLOC_EXIT                      | exit ->
| ANAlloc: allocate the node
ALLOC_COMMIT:
        MOVE.L  D3,(A3)                         | update the map
        MOVE.L  A2,A0                           | mark the node dirty
        JSR     P_mMarkBlock(PC)                | mark map node dirty
        SUBQ.L  #0x1,BTCFree(A4)                | adjust free block count
        BSET    #0x7,(A4)                       | mark BTCB dirty (BTCDirty)
        CLR     D0                              | indicate no error
        BSR     REL_MAP                         | ANExit: release map node
ALLOC_EXIT:
        MOVEM.L (A6)+,D2-D4/A2-A3               | Restore registers
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | return from ALLOC_EXIT

| P_mExtBTFile -- extend the file.
| ----------------------------------------------------------
|
| P_m Ext BT File
|
P_mExtBTFile:
        MOVE.L  (0x760).w,-(SP)                 | HFS vector: ExtBTFile
        RTS                                     | return from P_mExtBTFile

| ----------------------------------------------------------
|
| Ext BT File
|
ExtBTFile:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D2-D6/A2,-(A6)                  | save registers
| extend the BTree file space (data fork)
        MOVE    BTCRefNum(A4),D1                | file refnum
        MOVE.L  (FCBSPtr).w,A1                  | A1 = ptr(1st FCB)
        MOVE.L  0x14(A1,D1.W),A2                | A2 = ptr(VCB)
        MOVEQ.L #0x0,D3                         | no options
        MOVE.L  0x1E(A1,D1.W),D4                | request one clump (FCBClmpSize)
        JSR     P_mExtendFile(PC)               | extend the file
        BEQ.B   EXTBT_CALRANGE                  | got the space ->
        CMPI    #-0x22,D0                       | 'disk full' error? (DskFulErr)
        BNE     EXTBT_EXIT                      | no, some other error ->
        TST.L   D6                              | get any space?
        BEQ     EXTBT_EXIT                      | no, give up ->
| EFCalRange: calculate node number range for new space
EXTBT_CALRANGE:
        MOVE.L  BTCNNodes(A4),D3                | beg node # = current # of nodes
        MOVE.L  D3,D4                           | D3 and D4 = beg node #
        MOVE.L  0xC(A1,D1.W),D5                 | get new physical length (FCBPLen)
        DIVU    BTCNodeSize(A4),D5              | physical length / node size
        SWAP    D5                              | = number of nodes
        CLR     D5                              | clear remainder
        SWAP    D5                              | D5 = quotient (node count)
        MOVE.L  D5,BTCNNodes(A4)                | update total number of nodes
        SUBQ.L  #0x1,D5                         | # of nodes - 1 = node # of ending node
        MOVE.L  D5,D6                           | D5 and D6 = end node #
| locate map positions for beginning and end of new space
        SUBA.L  A2,A2                           | start with map record in header
EXTBT_GETMAP:
        BSR     GET_MAP                         | GetMap: get next map record
        BNE     EXTBT_EXIT                      | error ->
        EXT.L   D1                              | map size(bytes)
        LSL.L   #0x3,D1                         | x 8 = map size(bits)
        SUB.L   D1,D3                           | make relative begin/end node numbers
        SUB.L   D1,D5                           | relative to next map record
        BGE.B   EXTBT_ADDMAP                    | end node beyond this map ->
        SUBQ.L  #0x1,D4                         | adjust begin nodenum for no new map
        BRA     EXTBT_UPDFREE                   | update free count ->

| ----------------------------------------------------------
|
| EXTBT_ADDMAP
|
| EFAddMap: must extend the map
EXTBT_ADDMAP:
        TST.L   (A2)                            | have another map node? (NDFLink)
        BNE.B   EXTBT_GETMAP                    | yes, continue search ->
        MOVE.L  D4,(A2)                         | link new node to last node (NDFlink)
        TST.L   D3                              | new space begin within last map record?
        BGE.B   EXTBT_MARKOLD                   | no, must be all in new record ->
        ADD.L   D1,D3                           | make node number relative to this record
        DIVU    #0x8,D3                         | div node number by byte size
        MOVE    D3,D0                           | quotient = byte offset
        CLR     D3                              | clear quotient
        SWAP    D3                              | remainder = bit offset
        MOVEQ.L #0x7,D1                         | 7 - bit offset
        SUB.L   D3,D1                           | = bit index
        BSET    D1,0x0(A1,D0.W)                 | pre-allocate map node
        MOVEQ.L #-0x1,D3                        | indicate map node already allocated
EXTBT_MARKOLD:
        MOVE.L  A2,A0                           | mark the map node dirty
        JSR     P_mMarkBlock(PC)                | mark old map node dirty
        BSR     REL_MAP                         | RelMap: release the map node
        BNE.B   EXTBT_EXIT                      | error ->
| EFNewMap: initialize a new map node
        MOVE.L  D4,D1                           | map node number = begin node number
        JSR     InitNode(PC)                    | get an initialized node
        MOVE.L  A0,A2                           | A2 = ptr(new map node)
        MOVE.B  #0x2,NDType(A2)                 | set node type = NDMapNode (2)
        MOVE    #0x1,NDNRecs(A2)                | NDNRecs = 1 (map is one large record)
        MOVE    BTCNodeSize(A4),D1              | D1 = node size
        MOVEQ.L #-0x12,D0                       | map rec size = nodesize - lenND - 2*offsets
        ADD     D1,D0                           | D0 = nodesize - header - offsets
        LSR     #0x2,D0                         | round down
        LSL     #0x2,D0                         | to long word
        ADDI    #0xE,D0                         | rec offset = map rec size + lenND
        MOVE    D0,-0x4(A2,D1.W)                | set free space offset
        TST.L   D3                              | map node bit within new record?
        BLT.B   EXTBT_MARKNEW                   | no ->
        MOVE.B  #0x80,0xE(A2)                   | pre-allocate 1st node (map record at lenND)
EXTBT_MARKNEW:
        MOVE.L  A2,A0                           | mark the map node dirty
        JSR     P_mMarkBlock(PC)                | mark new map node dirty
| EFUpdFree: update free node count
EXTBT_UPDFREE:
        SUB.L   D4,D6                           | end node # - beg node # = # of nodes-1
        ADD.L   D6,BTCFree(A4)                  | adjust free node count
        BSET    #0x7,(A4)                       | mark BTCB dirty (BTCDirty)
        CLR.B   D0                              | result = 'ok'
        BSR     REL_MAP                         | RelMap: release last map node
| EFExit
EXTBT_EXIT:
        MOVEM.L (A6)+,D2-D6/A2                  | restore regs
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit ExtBTFile

| P_mFreeNode -- the disk node.
| ----------------------------------------------------------
|
| P_m Free Node
|
P_mFreeNode:
        MOVE.L  (0x75C).w,-(SP)                 | HFS vector: FreeNode
        RTS                                     | return from P_mFreeNode

| ----------------------------------------------------------
|
| Free Node
|
FreeNode:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D2-D3/A2,-(A6)                  | save registers
        MOVE.L  D1,D3                           | D3 = input node number
| locate map record for target node
        SUBA.L  A2,A2                           | indicate no node buffer
FREENODE_GETMAP:
        BSR     GET_MAP                         | GetMap: get next map record
        BNE.B   FREENODE_EXIT                   | didn't find it ->
        EXT.L   D1                              | map size(bytes)
        LSL.L   #0x3,D1                         | x 8 = map size(bits)
        SUB.L   D1,D3                           | node within this record?
        BGE.B   FREENODE_GETMAP                 | no, get next map record ->
| FNFound: found map record, mark node free
        ADD.L   D1,D3                           | make node number relative to this rec
        DIVU    #0x8,D3                         | div node number by byte size
        CLR.L   D0                              | clear high word
        MOVE    D3,D0                           | quotient = byte offset
        CLR     D3                              | clear quotient
        SWAP    D3                              | remainder = bit position
        MOVEQ.L #0x7,D1                         | 7 - bit position
        SUB.L   D3,D1                           | = bit index
        BCLR    D1,0x0(A1,D0.W)                 | mark node as free
        MOVE.L  A2,A0                           | mark the map node dirty
        JSR     P_mMarkBlock(PC)                | mark map node dirty
        ADDQ.L  #0x1,BTCFree(A4)                | adjust free count
        BSET    #0x7,(A4)                       | mark BTCB dirty (BTCDirty)
        CLR.B   D0                              | indicate no error
        BSR     REL_MAP                         | FNExit: release map node
FREENODE_EXIT:
        MOVEM.L (A6)+,D2-D3/A2                  | restore regs
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit FreeNode

| ----------------------------------------------------------
|
| GET_MAP
|
| GetMap: gets next allocation map record
GET_MAP:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
| release current map node
        MOVEQ.L #0x0,D2                         | assume map in header node
        MOVE.L  A2,D0                           | have a current node?
        BEQ.B   GETMAP_GETNODE                  | no, get header node ->
        MOVE.L  (A2),D2                         | get link to next map node (NDFLink)
        BSR     REL_MAP                         | RelMap: release the current map node
        BNE.B   GETMAP_EXIT                     | error ->
        TST.L   D2                              | have a next node?
        BNE.B   GETMAP_GETNODE                  | yes ->
        MOVEQ.L #0x20,D0                        | result = 'map record not found' (BTnotfound)
        BRA.B   GETMAP_EXIT                     | exit ->
| GMGetNode: get next map node
GETMAP_GETNODE:
        MOVEQ.L #0x0,D1                         | no GetBlock options
        JSR     P_mGetNode(PC)                  | get map node
        BNE.B   GETMAP_EXIT                     | error ->
        MOVE.L  A0,A2                           | A2 = ptr(node buffer)
| locate map record and calculate its size
        MOVEQ.L #0x0,D0                         | assume map record is record 0
        CMPI.B  #0x1,NDType(A2)                 | header node? (NDHdrNode = 1)
        BNE.B   GETMAP_LOCREC                   | no ->
        MOVEQ.L #0x2,D0                         | map record is record 2
GETMAP_LOCREC:
        MOVE.L  A2,A1                           | locate
        JSR     GetRecA(PC)                     | the record
        MOVE.L  A0,D1                           | D1 = ptr(record)
        MOVE    NDNRecs(A2),D0                  | locate the last record in node (NDNRecs)
        JSR     GetRecA(PC)                     | get ptr to last record
        MOVE.L  D1,A1                           | A1 = ptr(record)
        SUBA.L  A1,A0                           | map size = ptr(last record) - ptr(map record)
        MOVE    A0,D1                           | D1 = map size in bytes
        CLR     D0                              | result = ok
GETMAP_EXIT:
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit GetMap

| REL_MAP -- relMap: release map node.
| ----------------------------------------------------------
|
| REL_MAP
|
| Called by: ALLOC_FOUNDBIT, ALLOC_COMMIT, EXTBT_MARKOLD, EXTBT_UPDFREE, FREENODE_GETMAP (and 1 more)
REL_MAP:
        MOVE.L  (SP)+,-(A6)                     | Save return address to A6 stack
        MOVEM.L D1/A0-A1,-(A6)                  | Save registers
        MOVEQ.L #0x0,D1                         | no RelBlock options
        MOVE.L  A2,A0                           | ptr(node buffer)
        JSR     P_mRelNode(PC)                  | release the node
        SUBA.L  A2,A2                           | indicate no map node
        MOVEM.L (A6)+,D1/A0-A1                  | restore registers
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit RelMap

| RotateLT -- try rotating left.
| ----------------------------------------------------------
|
| Rotate LT
|
RotateLT:
        MOVEM.L D2-D7/A2-A5,-(SP)               | save regs
        MOVE.L  A0,A5                           | A5 = ptr(new record)
        MOVE    D0,D5                           | D5 = size of new record
| calculate split point
        MOVE.L  A2,A1                           | point to left node
        JSR     GetNodeSiz(PC)                  | get its size
        MOVE    D0,D2                           | D2 = left node size
        MOVE.L  A3,A1                           | point to right node
        JSR     GetNodeSiz(PC)                  | get its size
        ADD     D2,D0                           | right size + left size
        ADD     D5,D0                           | + (new record size + 2)
        ADDQ.W  #0x2,D0                         | = total data size
        LSR     #0x1,D0                         | total size / 2 = split point
        MOVE    D0,D6                           | D6 = split point
| simulate left rotation to determine best fit
        MOVE    NDNRecs(A2),D3                  | D3 = init virt indx = #recs in lt node
        MOVE    D1,D4                           | D4 = virtual insert index
        ADD     D3,D4                           | = rt insert indx + #recs in lt node
        MOVEQ.L #-0x1,D7                        | no current fit or previous fit
| RLFitLoop
ROTLT_FITLOOP:
        CMP     D3,D4                           | at insert point?
        BNE.B   ROTLT_GETREC                    | no ->
        ADD     D5,D2                           | include new record in lt size
        BRA.B   ROTLT_INCLOFF                   | ->

| ----------------------------------------------------------
|
| ROTLT_GETREC
|
ROTLT_GETREC:
        MOVE    D3,D0                           | convert virtual index
        SUB     NDNRecs(A2),D0                  | subtract NDNRecs from left node
        CMP     D4,D3                           | past insert point?
        BLE.B   ROTLT_ADJINDX                   | no, skip adjustment
        SUBQ.W  #0x1,D0                         | to a right node index
ROTLT_ADJINDX:
        JSR     GetRecA(PC)                     | get record size
        ADD     D0,D2                           | include record in lt size
ROTLT_INCLOFF:
        ADDQ.W  #0x2,D2                         | include offset also
| RLChkFit: check for a fit after simulated rotation
        MOVE    BTCNodeSize(A4),D1              | max node size
        SUBI    #0x10,D1                        | - length(ND) - 2 = max data size
        CMP     D1,D2                           | left node fit?
        BLE.B   ROTLT_CHKRT                     | yes ->
        SWAP    D7                              | have previous fit?
        TST     D7                              | check previous fit index
        BGE.B   ROTLT_DOROT                     | yes, use it ->
        MOVEQ.L #-0x1,D0                        | result = 'won't fit'
        BRA     ROTLT_EXIT                      | exit ->

| ----------------------------------------------------------
|
| ROTLT_CHKRT
|
ROTLT_CHKRT:
        MOVE    D6,D0                           | split point
        LSL     #0x1,D0                         | x 2 = total data size
        SUB     D2,D0                           | - lt size = rt size
        CMP     D1,D0                           | right node fit?
        BGT.B   ROTLT_CKSPLIT                   | no ->
        MOVE    D3,D7                           | save virtual index for this fit
| RLCkSplit: select best fit
ROTLT_CKSPLIT:
        CMP     D6,D2                           | reached split point?
        BLT.B   ROTLT_NEXTFIT                   | no ->
        BEQ.B   ROTLT_CHKFIT                    | right on the money ->
        SWAP    D7                              | past split point, try previous fit first
ROTLT_CHKFIT:
        TST     D7                              | have a fit?
        BGE.B   ROTLT_DOROT                     | yes, use it ->
        SWAP    D7                              | no, get previous fit
        TST     D7                              | have one?
        BGE.B   ROTLT_DOROT                     | yes, use it ->
ROTLT_NEXTFIT:
        SWAP    D7                              | previous fit = current fit
        MOVE    #-0x1,D7                        | no current fit
        ADDQ.W  #0x1,D3                         | bump index to next record
        MOVE    NDNRecs(A2),D1                  | max virtual index
        ADD     NDNRecs(A3),D1                  | = #recs in lt + #recs in rt
        CMP     D1,D3                           | any more records?
        BLE.B   ROTLT_FITLOOP                   | yes, keep trying ->
        MOVEQ.L #-0x1,D0                        | result = 'won't fit'
        BRA.B   ROTLT_EXIT                      | exit ->

| ----------------------------------------------------------
|
| ROTLT_DOROT
|
| RLRotate: we have a fit, do the actual rotation
ROTLT_DOROT:
        MOVE    NDNRecs(A2),D3                  | init virt indx = 1st rec in rt node
ROTLT_LOOP:
        CMP     D3,D4                           | at insert point?
        BNE.B   ROTLT_ROTREC                    | no ->
        MOVE.L  A2,A1                           | ptr(left node)
        MOVE.L  A5,A0                           | ptr(new record)
        MOVE    D5,D0                           | size of new record
        MOVE    0xA(A1),D1                      | insert index = end of node (NDNRecs)
        JSR     InsertRec(PC)                   | insert new record in left node
        BNE.B   ROTLT_FATAL                     | trouble ->
        MOVE.L  A1,A5                           | save ptr(node buffer) and index
        MOVE    D1,D5                           | for new record
        BRA.B   ROTLT_CHKSPLIT                  | ->

| ----------------------------------------------------------
|
| ROTLT_ROTREC
|
ROTLT_ROTREC:
        MOVE.L  A2,A0                           | ptr(left node)
        MOVE.L  A3,A1                           | ptr(right node)
        BSR     ROT_RECLT                       | RotRecLt: rotate 1st record
        BNE.B   ROTLT_FATAL                     | trouble ->
ROTLT_CHKSPLIT:
        CMP     D7,D3                           | reached split index?
        BEQ.B   ROTLT_CHKRT2                    | yes ->
        ADDQ.W  #0x1,D3                         | bump record index
        BRA.B   ROTLT_LOOP                      | rotate another one ->
| RLCheckRt: check if new record goes in right node
ROTLT_CHKRT2:
        CMP     D7,D4                           | insert index > split index?
        BLE.B   ROTLT_OK                        | no, not in right node ->
        MOVE.L  A3,A1                           | ptr(right node)
        MOVE.L  A5,A0                           | ptr(new record)
        MOVE    D5,D0                           | size of new record
        MOVE    D4,D1                           | insert index
        SUB     D7,D1                           | = virt insert index
        SUBQ.W  #0x1,D1                         | - split index - 1
        JSR     InsertRec(PC)                   | insert new record in right node
        BNE.B   ROTLT_FATAL                     | all done ->
        CLR     D0                              | result = 'ok'
        BRA.B   ROTLT_EXIT                      | exit ->

| ----------------------------------------------------------
|
| ROTLT_FATAL
|
ROTLT_FATAL:
        MOVEQ.L #0x40,D0                        | Load quick immediate
        _SysError                               | _SysError: fatal
| RLExit
ROTLT_OK:
        CLR     D0                              | result = ok
        MOVE.L  A5,A1                           | return ptr(node buffer) and index
        MOVE    D5,D1                           | for new record
ROTLT_EXIT:
        MOVEM.L (SP)+,D2-D7/A2-A5               | restore regs
        TST     D0                              | set condition codes
        RTS                                     | exit RotateLt

| SplitLT -- split left.
| ----------------------------------------------------------
|
| Split LT
|
SplitLT:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D3-D7/A3,-(A6)                  | save regs
| set up some common stuff
        MOVE.L  A0,D7                           | D7 = ptr(record)
        MOVE    D0,D6                           | D6 = size of record
        MOVE    D1,D5                           | D5 = insert index
        MOVE    BTCLevel(A4),D0                 | locate TPR
        JSR     LocTPR(PC)                      | for current level
        MOVE.L  (A0),D4                         | D4 = right node number (TPRNodeN)
| allocate a new disk node
        MOVE    BTCRefNum(A4),D0                | volume refnum
        JSR     P_mAllocNode(PC)                | allocate the node
        BNE.B   SPLITLT_EXIT                    | error ->
        MOVE.L  D1,D3                           | D3 = new left node number
| update forward link in original left node and release it
        MOVE.L  A2,D0                           | have a left node?
        BEQ.B   SPLITLT_INIT                    | no ->
        MOVE.L  D3,(A2)                         | left forward link = new node number
        MOVEQ.L #0x4,D1                         | indicate dirty buffer (RBDirty)
        MOVE.L  A2,A0                           | ptr(left node buffer)
        JSR     P_mRelNode(PC)                  | release left node
        BNE.B   SPLITLT_EXIT                    | error ->
| SLInit: initialize a new left node
SPLITLT_INIT:
        MOVE.L  D3,D1                           | new node number
        JSR     InitNode(PC)                    | get an initialized node
        MOVE.L  A0,A2                           | A2 = ptr(new left node)
        MOVE.B  NDType(A3),NDType(A2)           | set to same type as right node (NDType)
        MOVE.L  NDBlink(A3),0x4(A2)             | finish updating links (NDBlink)
        MOVE.L  D4,(A2)                         | NDFlink = right node number
        MOVE.L  D3,NDBlink(A3)                  | right node's BLink = new left node
        MOVEQ.L #0x1,D0                         | node height
        ADD     BTCDepth(A4),D0                 | = tree depth + 1
        SUB     BTCLevel(A4),D0                 | - current level
        MOVE.B  D0,0x9(A2)                      | NDNHeight
        CMPI.B  #0xFF,NDType(A2)                | adding a new leaf node? (NDLeafNode)
        BNE.B   SPLITLT_ROTATE                  | no ->
        TST.L   0x4(A2)                         | new 1st node? (NDBlink = 0?)
        BNE.B   SPLITLT_ROTATE                  | no ->
        MOVE.L  D3,BTCFNode(A4)                 | yes, update 1st node pointer
| SLRotate: insert new record via rotate left
SPLITLT_ROTATE:
        MOVE.L  D7,A0                           | ptr(new record)
        MOVE    D6,D0                           | size of new record
        MOVE    D5,D1                           | insert index
        JSR     RotateLT(PC)                    | insert via rotate left
        BEQ.B   SPLITLT_DONE                    | ok ->
        BRA.B   SPLITLT_EXIT                    | error ->
| SLExit
SPLITLT_DONE:
        CLR     D0                              | result = ok
        MOVE.L  D3,D2                           | return left node number in D2
SPLITLT_EXIT:
        MOVEM.L (A6)+,D3-D7/A3                  | restore regs
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit SplitLt

| TreeSearch -- treeSearch: descend B-tree from root to leaf for this key.
| ----------------------------------------------------------
|
| Tree Search
|
TreeSearch:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D3-D7/A2-A3,-(A6)               | save regs
        MOVE.L  A0,D7                           | D7 = ptr(search key)
        TST     BTCDepth(A4)                    | tree empty?
        BGT.B   TSRCH_START                     | no ->
        MOVEQ.L #0x20,D0                        | result = 'not found' (BTnotfound)
        SUBA.L  A1,A1                           | no node buffer
        CLR.L   D1                              | index = 0
        CLR.L   D2                              | node number = 0
        CLR     BTCLevel(A4)                    | current level = 0
        BRA     TSRCH_EXIT                      | exit ->

| ----------------------------------------------------------
|
| TSRCH_START
|
TSRCH_START:
        MOVEQ.L #0x1,D6                         | start at level 1
        MOVE.L  BTCRoot(A4),D3                  | root node number
| TSLoop: get the node and search for key
TSRCH_LOOP:
        MOVEQ.L #0x0,D1                         | no GetBlock options
        MOVE.L  D3,D2                           | node number
        JSR     P_mGetNode(PC)                  | get the node
        BNE     TSRCH_EXIT                      | error ->
        MOVE.L  A0,A1                           | A1 = ptr(node buffer)
        MOVE.L  D7,A0                           | ptr(search key)
        JSR     SearchNode(PC)                  | search node for key
        MOVE    D0,D5                           | D5 = search result
        MOVE    D1,D4                           | D4 = index
| TSUpdTPR: update TPR info
        MOVE    D6,D0                           | locate TPR
        JSR     LocTPR(PC)                      | for this level
        MOVE.L  A0,A3                           | A3 = ptr(TPR)
        MOVE.L  D3,(A3)                         | set node number (TPRNodeN)
        MOVE    D4,D2                           | assume parent index = insert index
        TST     D5                              | key found?
        BEQ.B   TSRCH_SETINDX                   | yes ->
        SUBQ.W  #0x1,D2                         | parent index = insert index - 1
        BGE.B   TSRCH_SETINDX                   | parent index >= 0, ok ->
        MOVE    D4,D2                           | use insert index
TSRCH_SETINDX:
        MOVE    D2,NDBlink(A3)                  | set record index (TPRRIndx)
        CMP     BTCDepth(A4),D6                 | at leaf level?
        BEQ.B   TSRCH_LEAF                      | yes, all done ->
| TSNxtLev: move to next level down
        MOVE    D2,D1                           | parent index
        MOVE.L  A1,-(SP)                        | save ptr to node buffer
        JSR     LocRec(PC)                      | locate child record
        MOVE.L  (A1),D3                         | D3 = child node number
        MOVE.L  (SP)+,A1                        | restore ptr to node buffer
        MOVEQ.L #0x0,D1                         | no RelBlock options
        MOVE.L  A1,A0                           | ptr(node buffer)
        JSR     P_mRelNode(PC)                  | release current node
        ADDQ.W  #0x1,D6                         | bump level count
        BRA.B   TSRCH_LOOP                      | continue the search
| TSDone: at leaf level, set up return info
TSRCH_LEAF:
        MOVE    D6,BTCLevel(A4)                 | initialize current level
        MOVE    D4,D1                           | return insert index in D1
        MOVE    D5,D0                           | return search result in D0
        MOVE.L  D3,D2                           | return node number in D2
TSRCH_EXIT:
        MOVEM.L (A6)+,D3-D7/A2-A3               | restore regs
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set up condition codes
        RTS                                     | exit TreeSearch

| ----------------------------------------------------------
|
| ROT_RECLT
|
| RotRecLt: rotates one record from right node into left node
ROT_RECLT:
        MOVEM.L A2-A3,-(SP)                     | save registers
        MOVE.L  A0,A2                           | A2 = ptr(lt node)
        MOVE.L  A1,A3                           | A3 = ptr(rt node)
        MOVEQ.L #0x0,D0                         | index of 1st record
        JSR     GetRecA(PC)                     | get the record size
        LEA.L   0xE(A1),A0                      | ptr(1st record) in rt node (lenND offset)
        MOVE.L  A2,A1                           | A1 = ptr(left node)
        MOVE    0xA(A1),D1                      | insert index into left node (NDNRecs)
        JSR     InsertRec(PC)                   | insert record in left node
        MOVE.L  A3,A1                           | A1 = ptr(right node)
        BEQ.B   ROTRECLT_DEL                    | insert ok ->
        MOVEQ.L #-0x1,D0                        | result = "won't fit"
        BRA.B   ROTRECLT_EXIT                   | exit ->
| RRLDelete: delete record from right node
ROTRECLT_DEL:
        CLR     D1                              | index = 0
        JSR     DeleteRec(PC)                   | delete it
        CLR     D0                              | result = ok
ROTRECLT_EXIT:
        TST     D0                              | set condition codes
        MOVEM.L (SP)+,A2-A3                     | restore registers
        RTS                                     | exit RotRecLt

| BuildIRec -- build index record.
| ----------------------------------------------------------
|
| Build I Rec
|
BuildIRec:
        MOVE.L  D2,-(SP)                        | save regs
        MOVE.L  D0,D2                           | save node number
        CLR     D0                              | locate 1st record
        BSR     GetRecA                         | in node
        MOVE.L  BTCVarPtr(A4),A1                | locate record buffer
        LEA.L   0x30(A1),A1                     | BTVRecord offset
        JSR     UpdIKey(PC)                     | move in the key
        BSR     GetMaxKey                       | node # offset = max key size
        MOVE.L  D2,0x0(A1,D0.W)                 | move in the node number
        MOVE.L  (SP)+,D2                        | restore regs
        RTS                                     | exit BuildIRec

| ChkNode -- validate node structure.
| ----------------------------------------------------------
|
| Chk Node
|
ChkNode:
        MOVEM.L D1-D2/A0-A2,-(SP)               | save registers
| check out the links
        MOVE    BTCRefNum(A4),D1                | locate the FCB
        MOVE.L  (FCBSPtr).w,A2                  | A2 = FCB array base
        MOVE.L  0xC(A2,D1.W),D0                 | PEOF / node size
        DIVU    BTCNodeSize(A4),D0              | = end node # + 1
        MOVEQ.L #0x0,D1                         | clear high word
        MOVE    D0,D1                           | D1 = end node # + 1
        CMP.L   (A1),D1                         | forward link within range? (NDFlink)
        BLS.B   CHKNODE_BAD                     | no, error ->
        CMP.L   0x4(A1),D1                      | backward link within range? (NDBlink)
        BLS     CHKNODE_BAD                     | no, error ->
| check node type (valid: $FF leaf to $02 map)
        MOVE.B  0x8(A1),D0                      | node type + 1 (NDType)
        ADDQ.B  #0x1,D0                         | increment for range check
        CMPI.B  #0x3,D0                         | (node type+1) > (max type+1)?
        BHI.B   CHKNODE_BAD                     | yes, error ->
| check node height
        MOVE.B  0x9(A1),D0                      | node height > tree depth? (NDNHeight)
        CMP.B   0x19(A4),D0                     | (BTCDepth+1)
        BHI.B   CHKNODE_BAD                     | yes, error ->
| CNChkNRecs: check number of records
        MOVEQ.L #0x0,D1                         | D1 = node size
        MOVE    BTCNodeSize(A4),D1              | from BTCB
        MOVEQ.L #-0xE,D0                        | max number of records
        ADD.L   D1,D0                           | = (node size - lenND)
        DIVU    #0x6,D0                         | / (min record size + offset word)
        CMP     0xA(A1),D0                      | record count within range? (NDNRecs)
        BCS     CHKNODE_BAD                     | no, error ->
| CNChkOff: check record offsets
        MOVE    0xA(A1),D1                      | loop index = # records
        MOVE    D1,D0                           | locate free space offset
        BSR     GetOffset                       | get offset for record D0
        MOVEQ.L #0x2,D2                         | prime previous offset to
        ADD.L   A0,D2                           | ptr(free space offset) + 2
        SUB.L   A1,D2                           | - ptr(node)
CHKNODE_OFFLOOP:
        MOVE    (A0)+,D0                        | get next offset
        BTST    #0x0,D0                         | odd offset?
        BNE.B   CHKNODE_BAD                     | yes, error ->
        CMPI    #0xE,D0                         | offset >= min (lenND)?
        BCS     CHKNODE_BAD                     | no, error ->
        CMP     D2,D0                           | offset < previous?
        BCC     CHKNODE_BAD                     | no, error ->
        MOVE    D0,D2                           | previous offset = current offset
        DBF     D1,CHKNODE_OFFLOOP              | check next one ->
        BRA.B   CHKNODE_OK                      | all done ->
| CNBadNode
CHKNODE_BAD:
        MOVEQ.L #0x24,D0                        | result = 'bad node' (BTBadNode)
        BRA.B   CHKNODE_EXIT                    | exit ->
| CNExit
CHKNODE_OK:
        CLR     D0                              | result = 'ok'
CHKNODE_EXIT:
        MOVEM.L (SP)+,D1-D2/A0-A2               | restore registers
        TST     D0                              | set up condition codes
        RTS                                     | exit ChkNode

| ClrNode -- zero out the node buffer.
| ----------------------------------------------------------
|
| Clr Node
|
ClrNode:
        MOVEM.L D0-D1/A0,-(SP)                  | Clear all 512 bytes of node
        MOVEQ.L #0x3,D1                         | D0 = 0 fill value
        ADD     BTCNodeSize(A4),D1              | D1 = 128 longwords - 1
        LSR     #0x2,D1                         | Clear loop
        SUBQ.W  #0x1,D1                         | Subtract
        MOVEQ.L #0x0,D0                         | clear the node buffer
CLRNODE_LOOP:
        MOVE.L  D0,(A0)+                        | zero a longword
        DBF     D1,CLRNODE_LOOP                 | loop until node cleared
        MOVEM.L (SP)+,D0-D1/A0                  | restore registers
        RTS                                     | exit ClrNode

| DeleteRec -- deleteRec: remove record at index D1 from node A3.
| ----------------------------------------------------------
|
| Delete Rec
|
DeleteRec:
        MOVEM.L D2-D6/A2-A5,-(SP)               | save regs
| set up some common stuff
        MOVE    D1,D5                           | save delete index
        MOVE    D1,D0                           | get delete offset
        JSR     GetOffset(PC)                   | get offset for record D0
        MOVE.L  A0,D6                           | D6 = ptr(delete offset)
        MOVE    D0,D4                           | D4 = delete offset
        LEA.L   -0x2(A0),A3                     | A3 = ptr(next offset)
        MOVE    (A3),D3                         | D3 = next offset
        MOVE    0xA(A1),D0                      | get last offset (NDNRecs)
        JSR     GetOffset(PC)                   | get free space offset
        MOVE.L  A0,A2                           | A2 = ptr(last offset)
        MOVE    D0,D2                           | D2 = last offset
| compress remaining records
        MOVE.L  A1,A5                           | save ptr(node buffer)
        LEA.L   0x0(A5,D3.W),A0                 | source = ptr(next record)
        LEA.L   0x0(A5,D4.W),A1                 | dest = ptr(delete record)
        MOVE    D2,D0                           | count = last offset
        SUB     D3,D0                           | - next offset
        JSR     MovRecLT(PC)                    | move the records
        SUBQ.W  #0x1,0xA(A5)                    | decrement number of records
| adjust the offsets
        MOVE.L  A3,A0                           | source = ptr(next offset)
        MOVE.L  D6,A1                           | dest = ptr(delete offset)
        MOVE    0xA(A5),D0                      | count = last index
        SUB     D5,D0                           | - delete index
        MOVE    D4,D1                           | delta = delete offset
        SUB     D3,D1                           | - next offset
        JSR     MovOffRT(PC)                    | adjust the offsets
        MOVEM.L (SP)+,D2-D6/A2-A5               | restore regs
        RTS                                     | exit DeleteRec

| GetLTSib -- getLTSib: get left sibling to update its forward link.
| ----------------------------------------------------------
|
| Get LT Sib
|
GetLTSib:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D2-D3,-(A6)                     | save registers
        CLR.B   D3                              | indicate GetLtSib
        BRA.B   GETSIB_COMMON                   | use common code

| GetRTSib -- getRTSib: get right sibling node.
| ----------------------------------------------------------
|
| Get RT Sib
|
GetRTSib:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D2-D3,-(A6)                     | save registers
        MOVEQ.L #0x1,D3                         | indicate GetRtSib
GETSIB_COMMON:
        TST.B   D3                              | getting left sibling?
        BNE.B   GETSIB_RIGHT                    | no ->
        MOVE.L  0x4(A0),D2                      | left sibling node number (NDBlink)
        BRA.B   GETSIB_GETNODE                  | ->
GETSIB_RIGHT:
        MOVE.L  (A0),D2                         | right sibling node number (NDFlink)
GETSIB_GETNODE:
        BNE.B   GETSIB_READ                     | we have the sibling ->
        CLR.L   D1                              | indicate no sibling
        BRA.B   GETSIB_NOERR                    | exit
GETSIB_READ:
        MOVEQ.L #0x0,D1                         | no GetBlock options
        BSR     P_mGetNode                      | get node from disk
        BNE.B   GETSIB_EXIT                     | error ->
        MOVE.L  D2,D1                           | return the node number
        MOVE.L  A0,A1                           | and buffer address
GETSIB_NOERR:
        CLR     D0                              | indicate no error
GETSIB_EXIT:
        MOVEM.L (A6)+,D2-D3                     | restore registers
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set up condition codes
        RTS                                     | exit GetLtSib/GetRtSib

| GetMaxKey -- max key length + 4.
| ----------------------------------------------------------
|
| Get Max Key
|
GetMaxKey:
        MOVEQ.L #0x1,D0                         | key length = 2 (include length byte)
        ADD     BTCKeyLen(A4),D0                | + max key length
        LSR     #0x1,D0                         | rounded down
        LSL     #0x1,D0                         | to word boundary
        RTS                                     | exit GetMaxKey

| P_mGetNode -- get the node.
| ----------------------------------------------------------
|
| P_m Get Node
|
| Called by: BTDEL_GETPAR, BTFlush, GR_GETNODE, BTINS_NXTLEV, BTSearch (and 4 more)
P_mGetNode:
        MOVE.L  (0x750).w,-(SP)                 | HFS vector: GetNode
        RTS                                     | return from P_mGetNode

| ----------------------------------------------------------
|
| Get Node
|
GetNode:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1/A1,-(A6)                     | Save registers
        MOVE    BTCRefNum(A4),D0                | D2 = node number (from D0, or from saved mark)
        MOVE.L  BTCCQPtr(A4),A1                 | D0 = BTCRefNum (B-tree file refnum for GetBlock)
        JSR     P_mGetBlock(PC)                 | D1 = GetBlock flags (GBexist if reusing)
        BNE.B   GETNODE_EXIT                    | A1 = BTCCQPtr (cache queue for this B-tree)
        MOVE.L  A0,A1                           | verify the node
        BSR     ChkNode                         | validate node structure
        BEQ.B   GETNODE_EXIT                    | its ok ->
        MOVE    D0,-(A6)                        | save result code
        MOVEQ.L #0x2,D1                         | set trash option (kRBTrash)
        MOVE.L  BTCCQPtr(A4),A1                 | ptr to cache queue
        JSR     P_mRelBlock(PC)                 | release it
        MOVE    (A6)+,D0                        | restore result code
GETNODE_EXIT:
        MOVEM.L (A6)+,D1/A1                     | restore registers
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set up condition codes
        RTS                                     | exit GetNode

| GetNodeSiz -- get its size.
| ----------------------------------------------------------
|
| Get Node Siz
|
GetNodeSiz:
        MOVE.L  D1,-(SP)                        | save registers
        MOVE    0xA(A1),D1                      | number of records in node (NDNRecs)
        MOVE    D1,D0                           | record data size
        JSR     GetOffset(PC)                   | = free space offset
        SUBI    #0xE,D0                         | - length of ND (lenND=14)
        LSL     #0x1,D1                         | NRecs x 2 = overhead for offsets
        ADD     D1,D0                           | rec data size + offsets = node data size
        MOVE.L  (SP)+,D1                        | restore registers
        RTS                                     | exit GetNodeSiz

| GetOffset -- get offset for record D0.
| ----------------------------------------------------------
|
| Get Offset
|
| Called by: DeleteRec, GetRecA, InsertRec, ChkNode, GetNodeSiz
GetOffset:
        BSR     GET_OFFA                        | get ptr(offset) first
        MOVE    (A0),D0                         | get the offset
        RTS                                     | return from GetOffset

| ----------------------------------------------------------
|
| GET_OFFA - GetOffA: get offset address
|
GET_OFFA:
        SUBA.L  A0,A0                           | position to offset base + 2
        MOVE    BTCNodeSize(A4),A0              | A0 = node size
        ADDA.L  A1,A0                           | A0 = end of node buffer
        LSL     #0x1,D0                         | index * 2 (bytes)
        NEG     D0                              | negative byte index
        LEA.L   -0x2(A0,D0.W),A0                | ptr(offset) = (base-2) + byte index
        RTS                                     | return from GET_OFFA

| GetRecA -- parent index record.
| ----------------------------------------------------------
|
| Get Rec A
|
| Called by: BTDEL_GETPAR, BTINS_NXTLEV, GETMAP_LOCREC, LocRec, ROTLT_ADJINDX (and 3 more)
GetRecA:
        MOVEM.L D1-D2,-(SP)                     | save registers
        MOVE    D0,D1                           | D1 = record index
        BSR.B   GetOffset                       | get offset of target record
        MOVE    D0,D2                           | D2 = target offset
        MOVE    D1,D0                           | get offset to next record
        ADDQ.W  #0x1,D0                         | next record index
        BSR.B   GetOffset                       | get offset of next record
        SUB     D2,D0                           | size = next offset - target offset
        LEA.L   0x0(A1,D2.W),A0                 | ptr(record) = base + offset
        MOVEM.L (SP)+,D1-D2                     | restore registers
        RTS                                     | return from GetRecA

| InitNode -- get an initialized node.
| ----------------------------------------------------------
|
| Init Node
|
InitNode:
        MOVE.L  (SP)+,-(A6)                     | save return address on A6 stack
        MOVEM.L D1-D2/A1,-(A6)                  | save registers
| get cache buffer for new node
        MOVE.L  D1,D2                           | node number
        MOVE    BTCRefNum(A4),D0                | file refnum
        MOVEQ.L #0x4,D1                         | no-read option (kGBnoread)
        MOVE.L  BTCCQPtr(A4),A1                 | cache queue ptr
        JSR     P_mGetBlock(PC)                 | get cache buffer
        BNE.B   INITNODE_EXIT                   | error ->
| initialize the node
        BSR     ClrNode                         | clear the node first
        MOVE    BTCNodeSize(A4),D2              | D2 = node size
        MOVE    #0xE,-0x2(A0,D2.W)              | set free space offset (lenND=14)
        CLR     D0                              | result = ok
INITNODE_EXIT:
        MOVEM.L (A6)+,D1-D2/A1                  | restore registers
        MOVE.L  (A6)+,-(SP)                     | put return address back on stack
        TST     D0                              | set condition codes
        RTS                                     | exit InitNode

| InsertRec -- try to insert it.
| ----------------------------------------------------------
|
| Insert Rec
|
| Called by: BTINS_NEWROOT, BTINS_INSERT, ROTLT_LOOP, ROTLT_CHKRT2, ROT_RECLT
InsertRec:
        MOVEM.L D1-D7/A1-A5,-(SP)               | save regs
| set up some common stuff
        MOVE    D0,D7                           | save size of record
        MOVE    D1,D6                           | save insert index
        MOVE.L  A0,D5                           | save ptr to record
        MOVE    D1,D0                           | insert index
        JSR     GetOffset(PC)                   | get offset for insert position
        MOVE    D0,D4                           | D4 = insert offset
        MOVE    0xA(A1),D0                      | number of keys = last index (NDNRecs)
        JSR     GetOffset(PC)                   | get free space offset
        MOVE.L  A0,A3                           | A3 = ptr(last offset)
        MOVE    D0,D3                           | D3 = last offset
| see if new record will fit
        MOVE.L  A3,D1                           | ptr(last offset)
        CLR.L   D0                              | clear high word
        MOVE    D3,D0                           | - (last offset + node base)
        ADD.L   A1,D0                           | D0 = absolute addr of free space
        SUB.L   D0,D1                           | = avail space
        MOVEQ.L #0x2,D0                         | 2 + record size
        ADD     D7,D0                           | = required size
        CMP     D0,D1                           | enough space?
        BGE.B   INSREC_FIT                      | yes ->
        MOVEQ.L #-0x1,D0                        | indicate "won't fit"
        BRA.B   INSREC_EXIT                     | exit

| ----------------------------------------------------------
|
| INSREC_FIT
|
| IRInsert: make hole for new record
INSREC_FIT:
        MOVE.L  A1,A5                           | A5 = ptr(node buffer)
        LEA.L   0x0(A5,D4.W),A0                 | source = ptr(insert record)
        LEA.L   0x0(A0,D7.W),A1                 | dest = source + size
        MOVE    D3,D0                           | last offset
        SUB     D4,D0                           | - insert offset = count
        JSR     MovRecRT(PC)                    | make hole for new record
| adjust offsets for moved records
        MOVE.L  A3,A0                           | source ptr = ptr to last offset
        LEA.L   -0x2(A0),A1                     | dest ptr = source ptr - 2
        MOVE    0xA(A5),D0                      | offset count =
        SUB     D6,D0                           | last index - insert index
        MOVE    D7,D1                           | delta = record size
        JSR     MovOffLT(PC)                    | adjust offsets left
| move in the new record
        MOVE.L  D5,A0                           | source = ptr(record)
        LEA.L   0x0(A5,D4.W),A1                 | dest = ptr(insert record)
        MOVE    D7,D0                           | count = record size
        JSR     MovRecLT(PC)                    | move record in
        ADDQ.W  #0x1,0xA(A5)                    | increment key count (NDNRecs)
        CLR     D0                              | result = ok
INSREC_EXIT:
        MOVEM.L (SP)+,D1-D7/A1-A5               | restore regs
        TST     D0                              | set condition codes
        RTS                                     | exit InsertRec

| LocBTCB -- locate the BTCB.
| ----------------------------------------------------------
|
| Loc BTCB
|
| Called by: BTClose, BTFlush, BTInsert, BTUpdate, BT_SETUP
LocBTCB:
        MOVE.L  (FCBSPtr).w,A4                  | start of FCBS
        MOVE.L  0x22(A4,D0.W),A4                | ptr(BTCB) from FCB (FCBBTCBptr)
        RTS                                     | exit LocBTCB

| LocRec -- in node.
| ----------------------------------------------------------
|
| Loc Rec
|
| Called by: BTDEL_UPDDEPTH, BTREC_FOUND, BTSRCH_FOUND, TSRCH_SETINDX, UpdDRec
LocRec:
        MOVEM.L D0/D2-D3,-(SP)                  | save registers
        MOVE    D1,D3                           | D3 = record index
        MOVE    D3,D0                           | locate
        JSR     GetRecA(PC)                     | the record
        MOVE.L  A0,D2                           | D2 = ptr(record)
        MOVE    D3,D0                           | locate
        ADDQ.W  #0x1,D0                         | next record index
        JSR     GetRecA(PC)                     | the next record
        MOVE.L  A0,D1                           | D1 = ptr(next record)
        MOVE.L  D2,A0                           | ptr(key) = ptr(record)
        MOVEQ.L #0x0,D0                         | get key length
        MOVE.B  (A0),D0                         | D0 = key length byte
        ADDQ.L  #0x2,D0                         | include length byte
        LSR.L   #0x1,D0                         | round up to word boundary
        LSL.L   #0x1,D0                         | adjust to word boundary
        SUB.L   D2,D1                           | record size = ptr(next record)
        SUB.L   D0,D1                           | - ptr(record) - (adj key length)
        MOVE.L  A0,A1                           | ptr(data record) = ptr(key)
        ADDA.L  D0,A1                           | + (adj key length)
        MOVEM.L (SP)+,D0/D2-D3                  | restore registers
        RTS                                     | exit LocRec

| LocTPR -- for this level.
| ----------------------------------------------------------
|
| Loc TPR
|
| Called by: BTDEL_FREENODE, BTDEL_GETPAR, BTINS_NXTLEV, BTINS_NEWROOT, SplitLT (and 1 more)
LocTPR:
        SUBQ.W  #0x1,D0                         | offset
        MULU    #0x6,D0                         | from beg of table (LenTPR=6)
        MOVE.L  BTCVarPtr(A4),A0                | ptr to BTree buffer
        LEA.L   0x0(A0,D0.L),A0                 | get ptr(TPR)
        RTS                                     | exit LocTPR

| ----------------------------------------------------------
|
| Mov Off LT - move offsets left within a single node
|
MovOffLT:
        MOVEM.L D0-D2/A0-A1,-(SP)               | save regs
MOVOFFLT_LOOP:
        MOVE    (A0)+,D2                        | *ptrDst++ = *ptrSrc++ + delta
        ADD     D1,D2                           | adjust by delta
        MOVE    D2,(A1)+                        | store adjusted offset
        DBF     D0,MOVOFFLT_LOOP                | loop for all offsets
        BRA.B   MOVOFF_RETURN                   | return

| ----------------------------------------------------------
|
| Mov Off RT - move offsets right within a single node
|
MovOffRT:
        MOVEM.L D0-D2/A0-A1,-(SP)               | save regs
        CMPM    (A0)+,(A1)+                     | preincrement A0, A1 for loop
MOVOFFRT_LOOP:
        MOVE    -(A0),D2                        | *ptrDst-- = *ptrSrc-- + delta
        ADD     D1,D2                           | adjust by delta
        MOVE    D2,-(A1)                        | store adjusted offset
        DBF     D0,MOVOFFRT_LOOP                | loop for all offsets
MOVOFF_RETURN:
        MOVEM.L (SP)+,D0-D2/A0-A1               | restore regs
        RTS                                     | exit MovOffRT and return to caller

| ----------------------------------------------------------
|
| Mov Rec LT
|
| MovRecLt: move records left within a single node
MovRecLT:
        MOVEM.L D0-D1/A0-A1,-(SP)               | save regs
        TST     D0                              | test byte count
        BLE.B   MOVRECLT_EXIT                   | byte count <= 0
        SUBQ.W  #0x1,D0                         | adjust loop index
MOVRECLT_LOOP:
        MOVE.B  (A0)+,(A1)+                     | move one byte, ascending
        DBF     D0,MOVRECLT_LOOP                | for all D0+1 bytes
MOVRECLT_EXIT:
        MOVEM.L (SP)+,D0-D1/A0-A1               | restore regs
        RTS                                     | return from MOVRECLT_EXIT

| ----------------------------------------------------------
|
| Mov Rec RT - move records right within a single node
|
MovRecRT:
        MOVEM.L D0-D1/A0-A1,-(SP)               | save regs
        TST     D0                              | check byte count
        BLE.B   MOVRECRT_EXIT                   | byte count <= 0
        ADDA    D0,A0                           | high-address of source block
        ADDA    D0,A1                           | high-address of dest block
        SUBQ.W  #0x1,D0                         | byte count - 1
MOVRECRT_LOOP:
        MOVE.B  -(A0),-(A1)                     | move one byte, descending from the high end
        DBF     D0,MOVRECRT_LOOP                | for all D0+1 bytes
MOVRECRT_EXIT:
        MOVEM.L (SP)+,D0-D1/A0-A1               | restore regs
        RTS                                     | return from MOVRECRT_EXIT

| P_mRelNode -- release the node.
| ----------------------------------------------------------
|
| P_m Rel Node
|
| Called by: BTINS_CLEANUP, BTDEL_CHKRECS, BTDEL_GETRSIB, BTDEL_FREENODE, BTDEL_RELCHILD (and 12 more)
P_mRelNode:
        MOVE.L  (0x754).w,-(SP)                 | HFS vector: RelNode
        RTS                                     | return from P_mRelNode

| ----------------------------------------------------------
|
| Rel Node
|
RelNode:
        MOVE.L  (SP)+,-(A6)                     | Save return address
        MOVE.L  A1,-(A6)                        | Save A4
        MOVE.L  A0,D0                           | A0 = node data pointer -> not nil?
        BEQ.B   RELNODE_SKIP                    | Nil: skip release
        JSR     P_mRelBlock(PC)                 | Release block via cache (RelBlock)
RELNODE_SKIP:
        MOVE.L  (A6)+,A1                        | Restore A4
        MOVE.L  (A6)+,-(SP)                     | restore return address
        TST     D0                              | Set Z flag
        RTS                                     | return from RELNODE_SKIP

| SearchNode -- binary search within node.
| ----------------------------------------------------------
|
| Search Node
|
SearchNode:
        MOVEM.L D2-D5/A1-A3,-(SP)               | save regs
| set up some common stuff
        MOVE.L  A0,A3                           | A3 = ptr(search key)
        MOVE.L  A1,A2                           | A2 = ptr(node buffer)
        MOVE.L  BTCKeyCR(A4),D5                 | D5 = ptr(key compare routine)
| search node for key using a binary search
        CLR     D2                              | lower bnd = 0
        MOVE    NDNRecs(A2),D3                  | upper bnd = number of recs - 1 (NDNRecs)
        SUBQ.W  #0x1,D3                         | adjust to 0-based index
        CMP     D3,D2                           | while lower bnd <= upper bnd
        BGT.B   SRCHNODE_NOTFND                 | search exhausted, not found
| SrchLoop
SRCHNODE_LOOP:
        MOVE    D2,D4                           | index = (upper+lower) / 2
        ADD     D3,D4                           | D4 = lower + upper
        LSR     #0x1,D4                         | D4 = new index
        MOVE    D4,D0                           | get ptr(trial key)
        MOVE.L  A2,A1                           | A1 = node buffer
        JSR     GetRecA(PC)                     | get trial record
        MOVE.L  A0,A1                           | A1 = ptr(trial key)
        MOVE.L  A3,A0                           | A0 = ptr(search key)
        MOVE.L  A4,-(SP)                        | save A4
        MOVE.L  D5,A4                           | A4 = ptr(key compare routine)
        JSR     (A4)                            | compare the keys
        MOVE.L  (SP)+,A4                        | restore A4
        TST     D0                              | test result code
        BEQ.B   SRCHNODE_EQ                     | search key = trial key ->
        BGT.B   SRCHNODE_GT                     | search key > trial key ->
| SrchLT: search key < trial key
        MOVE    D4,D3                           | upper = index - 1
        SUBQ.W  #0x1,D3                         | D3 = new upper bound
        CMP     D3,D2                           | upper <= lower?
        BLE.B   SRCHNODE_LOOP                   | no, continue binary search
        BRA.B   SRCHNODE_NOTFND                 | yes, search exhausted
| SrchEQ
SRCHNODE_EQ:
        CLR     D0                              | result = FOUND
        BRA.B   SRCHNODE_EXIT                   | Lower > upper? (search exhausted)

| ----------------------------------------------------------
|
| SRCHNODE_GT
|
| SrchGT: search key > trial key
SRCHNODE_GT:
        MOVE    D4,D2                           | lower = index + 1
        ADDQ.W  #0x1,D2                         | D2 = new lower bound
        CMP     D3,D2                           | lower <= upper?
        BLE.B   SRCHNODE_LOOP                   | yes, continue binary search
| SrchExit
SRCHNODE_NOTFND:
        MOVE    D2,D4                           | index = lower
        MOVEQ.L #0x20,D0                        | result = 'not found' (BTnotfound)
| SrchRet
SRCHNODE_EXIT:
        MOVE    D4,D1                           | return index in D1
        MOVEM.L (SP)+,D2-D5/A1-A3               | restore regs
        TST     D0                              | set up condition codes
        RTS                                     | exit SearchNode

| UpdDRec -- replace the junk data record.
| ----------------------------------------------------------
|
| Upd D Rec
|
UpdDRec:
        MOVEM.L D0-D1/A0-A2,-(SP)               | save registers
        MOVE.L  A0,A2                           | A2 = ptr(data record)
        JSR     LocRec(PC)                      | locate data position in BTree record
        MOVE.L  A2,D1                           | ptr(data record)
        BEQ.B   UPDDREC_CLR                     | ptr = 0, clear the record ->
        MOVE.L  D1,A0                           | source = data record
        EXT.L   D0                              | move length = record size
        _BlockMove                              | move in the data record
        BRA.B   UPDDREC_EXIT                    | all done ->
UPDDREC_CLRLOOP:
        CLR.B   (A1)+                           | clear the record
UPDDREC_CLR:
        DBF     D0,UPDDREC_CLRLOOP              | loop until record cleared
UPDDREC_EXIT:
        MOVEM.L (SP)+,D0-D1/A0-A2               | restore registers
        RTS                                     | exit UpdDRec

| ----------------------------------------------------------
|
| Upd I Key - update key portion of an index record
|
UpdIKey:
        MOVEM.L D0-D1/A0-A2,-(SP)               | save regs
        MOVE.L  A0,A2                           | save ptr(source key)
        MOVE    BTCKeyLen(A4),D1                | get max key length
        MOVE.B  D1,(A1)+                        | stuff max key length
        MOVE.L  A2,A0                           | ptr(source key)
        MOVE.B  (A0)+,D0                        | source key length
        EXT     D0                              | sign-extend to word
        SUB     D0,D1                           | max key length - source key length
        BGE.B   UPDIKEY_CPYTEST                 | length ok ->
        ADD     D1,D0                           | source > max, use max length
        BRA.B   UPDIKEY_CPYTEST                 | start copying key bytes
UPDIKEY_CPYLOOP:
        MOVE.B  (A0)+,(A1)+                     | copy next byte
UPDIKEY_CPYTEST:
        DBF     D0,UPDIKEY_CPYLOOP              | loop for all key bytes
        TST     D1                              | need any null padding?
        BLE.B   UPDIKEY_EXIT                    | no ->
        BRA.B   UPDIKEY_PADTEST                 | start null padding
UPDIKEY_PADLOOP:
        CLR.B   (A1)+                           | clear next byte in key (null pad)
UPDIKEY_PADTEST:
        DBF     D1,UPDIKEY_PADLOOP              | loop for remaining padding bytes
UPDIKEY_EXIT:
        MOVEM.L (SP)+,D0-D1/A0-A2               | restore regs
        RTS                                     | exit UpdIKey

