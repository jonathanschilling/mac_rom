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

BTSVCS:                                         | Apple source module (MacSEROM.lst)
BTCLOSE:
    MOVE.L      (0x730).W,-(A7)                 | HFS vector: BTClose trampoline
    RTS                                         | dispatch via vector
VBTCLOSE:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1-D4/A0-A4,-(A6)               | save regs
    MOVE.W      D0,D3                           | D3 = B-tree file refnum
    MOVE.W      D3,D0                           | D0 = refnum for LocBTCB
    JSR         LOCBTCB(PC)                     | find BTCB for this B-tree -> A4
    JSR         BTFLUSH(PC)                     | flush B-tree header to disk
    BNE.B       BTCLOSE_EXIT                    | error ->
    MOVE.W      D3,D0                           | refnum for cache flush
    MOVEQ.L     #0x1,D1                         | D1 = kFCtrash (trash all cached blocks)
    MOVEA.L     0x8(A4),A1                      | A1 = B-tree cache queue (BTCCQPtr)
    JSR         FLUSHCACHE(PC)                  | flush and invalidate all cached nodes
    BNE.B       BTCLOSE_EXIT                    | error ->
    MOVEA.L     A4,A0                           | A0 = BTCB pointer
    _DisposePtr                                 | free BTCB memory block
    MOVEA.L     (FCBSPtr).W,A4                  | A4 = FCB array base
    CLR.L       0x22(A4,D3.W)                   | clear FCB BTCB extension ptr
    CLR.W       D0                              | result = noErr
BTCLOSE_EXIT:
    MOVEM.L     (A6)+,D1-D4/A0-A4               | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from BTClose
| Called by: CMDELETECN_DODELETE, DEALLOCFILE_NO_2, TRUNCATEFILE_OK, CC_CLR_THD_LOOP, MC_UPD_DEST (and 1 more)
BTDELETE:
    MOVE.L      (0x734).W,-(A7)                 | HFS vector: BTDelete trampoline
    RTS                                         | dispatch via vector
VBTDELETE:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1-D5/A0-A4,-(A6)               | save regs
    BSR.W       BT_SETUP                        | BT_SETUP: find BTCB -> A4
    CLR.L       0x12(A4)                        | clear BTCNodeM (no node mark)
    SUBA.L      A2,A2                           | A2 = nil (no secondary node)
    SUBA.L      A3,A3                           | A3 = nil (no primary node)
    JSR         TREESEARCH(PC)                  | descend B-tree to find key
    MOVEA.L     A1,A3                           | A3 = leaf node with key
    BNE.W       BTDEL_CLEANUP                   | key not found ->
    MOVE.W      D1,D5                           | D5 = record index in node
| BTDelRec: delete record from current node
BTDEL_DELREC:
    MOVEA.L     A3,A1                           | A1 = node buffer for DeleteRec
    MOVE.W      D5,D1                           | D1 = record index
    JSR         DELETEREC(PC)                   | remove record from node
    MOVEA.L     A3,A0                           | A0 = node buffer
    JSR         MARKBLOCK(PC)                   | mark node dirty in cache
    TST.W       D5                              | at root level? (index 0)
    BNE.B       BTDEL_CHKLEAF                   | no ->
    BSET        #0x6,(A4)                       | set BTCKeyUpd: index key changed
BTDEL_CHKLEAF:
    CMPI.B      #0xFF,0x8(A3)                   | leaf node? (NDType=0xFF)
    BNE.B       BTDEL_CHKRECS                   | no ->
    SUBQ.L      #0x1,0x1E(A4)                   | decrement leaf record count (BTCNRecs)
| BTDelChkRecs: check if node is empty
BTDEL_CHKRECS:
    TST.W       0xA(A3)                         | any records left? (NDNRecs)
    BGT.B       BDNXTLEV                        | yes, skip to next level ->
| node empty: update sibling links
    MOVEA.L     A3,A0                           | A0 = empty node
    JSR         GETLTSIB(PC)                    | get left sibling
    BNE.W       BTDEL_CLEANUP                   | error ->
    TST.L       D1                              | has left sibling?
    BEQ.B       BTDEL_GETRSIB                   | no ->
    MOVE.L      (A3),(A1)                       | left->NDFLink = deleted->NDFLink
    MOVEQ.L     #0x4,D1                         | D1 = RBdirty
    MOVEA.L     A1,A0                           | A0 = left sibling
    JSR         RELNODE(PC)                     | release left sibling (dirty)
BTDEL_GETRSIB:
    MOVEA.L     A3,A0                           | A0 = empty node
    JSR         GETRTSIB(PC)                    | get right sibling
    BNE.W       BTDEL_CLEANUP                   | error ->
    TST.L       D1                              | has right sibling?
    BEQ.B       BTDEL_UPDPTRS                   | no ->
    MOVE.L      0x4(A3),0x4(A1)                 | right->NDBLink = deleted->NDBLink
    MOVEQ.L     #0x4,D1                         | D1 = RBdirty
    MOVEA.L     A1,A0                           | A0 = right sibling
    JSR         RELNODE(PC)                     | release right sibling (dirty)
| BDUpdPtrs: update first and last leaf node pointers
BTDEL_UPDPTRS:
    CMPI.B      #0xFF,0x8(A3)                   | leaf node? (NDType=0xFF)
    BNE.B       BDFREE                          | no ->
    TST.L       0x4(A3)                         | backward link = 0? (NDBLink)
    BNE.B       BTDEL_CHKFLINK                  | no ->
    MOVE.L      (A3),0x22(A4)                   | update first leaf node (BTCFNode)
BTDEL_CHKFLINK:
    TST.L       (A3)                            | forward link = 0? (NDFLink)
    BNE.B       BDFREE                          | no ->
    MOVE.L      0x4(A3),0x26(A4)                | update last leaf node (BTCLNode)
| BDFree: free the empty node
BDFREE:
    MOVEA.L     A3,A0                           | A0 = empty node
    JSR         CLRNODE(PC)                     | zero out node buffer
    MOVEQ.L     #0x4,D1                         | D1 = RBdirty
    JSR         RELNODE(PC)                     | release node buffer (dirty)
    SUBA.L      A3,A3                           | A3 = nil (no buffer held)
    MOVE.W      0x10(A4),D0                     | current level (BTCLevel)
    JSR         LOCTPR(PC)                      | locate TPR for this level
    MOVE.L      (A0),D1                         | D1 = node number to free
    MOVE.W      0x2(A4),D0                      | B-tree file refnum (BTCRefNum)
    JSR         FREENODE(PC)                    | free the disk node
    BSET        #0x4,(A4)                       | set BTCDelIRec: delete parent index
    BCLR        #0x6,(A4)                       | clear BTCKeyUpd: no key update
| BDNxtLev: move to next level up
BDNXTLEV:
    SUBQ.W      #0x1,0x10(A4)                   | bump to next level up (BTCLevel)
    BEQ.B       BTDEL_ROOT                      | reached root ->
    BTST        #0x6,(A4)                       | key update required? (BTCKeyUpd)
    BNE.B       BTDEL_GETPAR                    | yes ->
    BTST        #0x4,(A4)                       | index record delete needed? (BTCDelIRec)
    BEQ.W       BTDEL_DONE                      | no, all done ->
| BTDelGetPar: get parent node
BTDEL_GETPAR:
    MOVE.W      0x10(A4),D0                     | current level (BTCLevel)
    JSR         LOCTPR(PC)                      | locate TPR for this level
    MOVE.W      0x4(A0),D5                      | D5 = parent record index (TPRRIndx)
    MOVE.L      (A0),D2                         | D2 = parent node number (TPRNodeN)
    MOVEQ.L     #0x0,D1                         | get node without write
    JSR         GETNODE(PC)                     | read parent node into cache
    BNE.W       BTDEL_CLEANUP                   | error ->
    MOVEA.L     A0,A2                           | A2 = parent node buffer
| BDUpdKey: update parent index key if needed
    BTST        #0x6,(A4)                       | key update required? (BTCKeyUpd)
    BEQ.B       BTDEL_RELCHILD                  | no ->
    MOVE.W      D5,D0                           | locate parent index record
    MOVEA.L     A2,A1                           | A1 = parent node
    JSR         GETRECA(PC)                     | get parent record -> A0
    MOVE.L      A0,-(A7)                        | save ptr to parent record
    MOVEA.L     A3,A1                           | A1 = child node
    CLR.W       D0                              | record 0 (first key)
    JSR         GETRECA(PC)                     | get first key in child
    MOVEA.L     (A7)+,A1                        | A1 = parent index record
    JSR         UPDIKEY(PC)                     | update parent key from child
    MOVEA.L     A2,A0                           | A0 = parent node
    JSR         MARKBLOCK(PC)                   | mark parent dirty
    TST.W       D5                              | update to 1st key in node?
    BEQ.B       BTDEL_RELCHILD                  | yes, leave BTCKeyUpd set ->

| BTDelRelChild: release child and promote parent
    BCLR        #0x6,(A4)                       | clear BTCKeyUpd (no more key update)
BTDEL_RELCHILD:
    MOVEQ.L     #0x0,D1                         | release without write
    MOVEA.L     A3,A0                           | A0 = child node buffer
    JSR         RELNODE(PC)                     | release child node
    MOVEA.L     A2,A3                           | promote parent to current node
    MOVE.W      D2,D3                           | D3 = parent node number
    BCLR        #0x4,(A4)                       | index record delete needed? (BTCDelIRec)
    BEQ.B       BTDEL_CHKUPD                    | no ->
    BRA.W       BTDEL_DELREC                    | yes, delete parent index record ->
| BTDelChkUpd: check if another key update needed
BTDEL_CHKUPD:
    BTST        #0x6,(A4)                       | key update required? (BTCKeyUpd)
    BNE.B       BDNXTLEV                        | yes, go to next level ->
    BRA.B       BTDEL_DONE                      | no, all done ->
| BDRoot: reached root level, check for empty/collapsible tree
BTDEL_ROOT:
    MOVE.L      A3,D0                           | root node released?
    BNE.B       BTDEL_UPDDEPTH                  | no ->
    CLR.W       0x18(A4)                        | set tree to empty (BTCDepth=0)
    CLR.L       0x1A(A4)                        | no root node (BTCRoot=0)
    BRA.B       BTDEL_DONE                      | exit ->
| BDUpdDepth: collapse root if it has <= 1 index record
BTDEL_UPDDEPTH:
    CMPI.W      #0x1,0xA(A3)                    | root has > 1 record? (NDNRecs)
    BGT.B       BTDEL_DONE                      | yes, done ->
    TST.B       0x8(A3)                         | index node? (NDType=0 for index)
    BNE.B       BTDEL_DONE                      | no (leaf), done ->
    SUBQ.W      #0x1,0x18(A4)                   | decrement tree depth (BTCDepth)
    MOVEQ.L     #0x0,D1                         | record 0 (first/only record)
    MOVEA.L     A3,A1                           | A1 = root node buffer
    JSR         LOCREC(PC)                      | locate first record
    MOVE.L      (A1),0x1A(A4)                   | new root = child node (BTCRoot)
    MOVEA.L     A3,A0                           | A0 = old root node
    JSR         CLRNODE(PC)                     | zero out old root
    MOVEQ.L     #0x4,D1                         | D1 = RBdirty
    JSR         RELNODE(PC)                     | release old root (dirty)
    SUBA.L      A3,A3                           | A3 = nil (no buffer)
    MOVE.L      D3,D1                           | D1 = old root node number
    MOVE.W      0x2(A4),D0                      | B-tree file refnum (BTCRefNum)
    JSR         FREENODE(PC)                    | free old root node
    MOVE.L      0x1A(A4),D3                     | D3 = new root node number
    MOVE.L      D3,D2                           | D2 = node number for GetNode
    MOVEQ.L     #0x0,D1                         | no options
    JSR         GETNODE(PC)                     | read new root into cache
    BNE.B       BTDEL_CLEANUP                   | error ->
    MOVEA.L     A0,A3                           | A3 = new root node
    BRA.B       BTDEL_UPDDEPTH                  | check if further collapse needed ->
| BDExit: mark BTCB dirty and return
| Called by: BTDEL_UPDDEPTH, BDNXTLEV, BTDEL_CHKUPD, BTDEL_ROOT
BTDEL_DONE:
    BSET        #0x7,(A4)                       | mark BTCB dirty (BTCDirty)
    CLR.W       D0                              | result = noErr
| BTDelCleanup: release node and exit
| Called by: VBTDELETE, BTDEL_CHKRECS, BTDEL_GETRSIB, BTDEL_GETPAR, BTDEL_UPDDEPTH
BTDEL_CLEANUP:
    MOVE.W      D0,-(A6)                        | save result code
    MOVEA.L     A3,A0                           | A0 = node buffer
    MOVEQ.L     #0x0,D1                         | release without write
    JSR         RELNODE(PC)                     | release node buffer
    MOVE.W      (A6)+,D0                        | restore result code
    BSR.W       BT_CLEANUP                      | BTCleanUp: release BTCB
    MOVEM.L     (A6)+,D1-D5/A0-A4               | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from BTDelete
BTFLUSH:
    MOVE.L      (0x738).W,-(A7)                 | HFS vector: BTFlush trampoline
    RTS                                         | dispatch via vector
VBTFLUSH:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1-D4/A0-A4,-(A6)               | save regs
    MOVE.W      D0,D3                           | D3 = file refnum
    MOVEA.L     (FCBSPtr).W,A1                  | A1 = FCB array base
    MOVEA.L     0x14(A1,D3.W),A2                | A2 = VCB pointer (FCBVPtr)
    TST.W       0x48(A2)                        | volume offline? (vcbDrvNum)
    BEQ.B       BTFLUSH_EXIT                    | yes, nothing to flush ->
    JSR         LOCBTCB(PC)                     | locate BTCB -> A4
    BCLR        #0x7,(A4)                       | BTCB dirty? (BTCDirty)
    BEQ.B       BTFLUSH_CACHE                   | no, just flush cache ->
| write BTCB header fields to disk node 0
    MOVEQ.L     #0x0,D1                         | no options
    MOVEQ.L     #0x0,D2                         | BTH is disk block 0
    JSR         GETNODE(PC)                     | read header node into cache
    BNE.B       BTFLUSH_EXIT                    | error ->
    MOVEA.L     A0,A3                           | A3 = header node buffer
    MOVE.W      #0x1D,D0                        | LenMemBTH-1 = 29 ($1D)
    LEA.L       0x18(A4),A0                     | source = BTCB header fields (BTCDepth)
    LEA.L       0xE(A3),A1                      | dest = BTH in node (after ND)
BTFLUSH_CPYLOOP:
    MOVE.B      (A0)+,(A1)+                     | copy BTCB header to node
    DBF.W       D0,BTFLUSH_CPYLOOP              | loop for all bytes
    MOVEQ.L     #0x4,D1                         | D1 = RBdirty
    MOVEA.L     A3,A0                           | A0 = header node buffer
    JSR         RELNODE(PC)                     | release header node (dirty)
    BNE.B       BTFLUSH_EXIT                    | error ->
| BFFlush: flush the cache for this file
BTFLUSH_CACHE:
    MOVE.W      D3,D0                           | file refnum
    MOVEQ.L     #0x0,D1                         | no FlushCache options
    MOVEA.L     0x8(A4),A1                      | A1 = cache queue ptr (BTCCQPtr)
    JSR         FLUSHCACHE(PC)                  | flush B-tree cache to disk
| BFExit
BTFLUSH_EXIT:
    MOVEM.L     (A6)+,D1-D4/A0-A4               | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from BTFlush
BTGETRECORD:
    MOVE.L      (0x73C).W,-(A7)                 | HFS vector: BTGetRecord trampoline
    RTS                                         | dispatch via vector
VBTGETRECORD:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D3-D5/A2-A4,-(A6)               | save regs
    BSR.W       BT_SETUP                        | BT_SETUP: find BTCB -> A4
    MOVE.W      D1,D5                           | D5 = selection code (offset)
    SUBA.L      A3,A3                           | no node buffer yet
    MOVE.W      0x16(A4),D4                     | D4 = current index mark (BTCIndexM)
    MOVE.L      0x12(A4),D3                     | D3 = current node mark (BTCNodeM)
    BNE.B       BTREC_LOCATE                    | valid node ->
    MOVEQ.L     #0x20,D0                        | result = BTnotfound
    BRA.B       BTREC_EXIT                      | exit ->
| GRLocate: adjust index by selection code
BTREC_LOCATE:
    ADD.W       D5,D4                           | D4 = adjusted index
| GRGetNode: release current, get node D3
BTREC_GRGETNODE:
    BSR.B       GR_GETNODE                      | release old, get node D3 -> A3
    BNE.B       BTREC_EXIT                      | error ->
| GRChkIndx: check index bounds
BTREC_CHKINDX:
    TST.W       D4                              | index < 0?
    BLT.B       BTREC_GETPREV                   | yes, get previous node ->
    MOVE.W      0xA(A3),D1                      | D1 = records in node (NDNRecs)
    CMP.W       D1,D4                           | index within node?
    BLT.B       BTREC_FOUND                     | yes, found it ->
    MOVE.L      (A3),D0                         | next node (NDFLink)
    BEQ.B       BTREC_ATEND                     | no more nodes ->
    MOVE.L      D0,D3                           | D3 = next node number
    SUB.W       D1,D4                           | adjust index past this node
    BRA.B       BTREC_GRGETNODE                 | try next node ->
| GRAtEnd: at end of chain, use last record as mark
BTREC_ATEND:
    MOVE.W      D1,D4                           | index = last record
    SUBQ.W      #0x1,D4                         | adjust to 0-based
    BRA.B       BTREC_SETMARK                   | set mark and exit ->
| GRGetPrev: get previous node
BTREC_GETPREV:
    MOVE.L      0x4(A3),D0                      | previous node (NDBLink)
    BEQ.B       BTREC_ATBEGIN                   | no previous ->
    MOVE.L      D0,D3                           | D3 = previous node number
    BSR.B       GR_GETNODE                      | release old, get node D3
    BNE.B       BTREC_EXIT                      | error ->
    ADD.W       0xA(A3),D4                      | adjust index by prev node's count
    BRA.B       BTREC_CHKINDX                   | check bounds again ->
| GRAtBegin: at beginning of chain
BTREC_ATBEGIN:
    MOVEQ.L     #0x0,D4                         | index = first record
BTREC_SETMARK:
    MOVE.L      D3,0x12(A4)                     | update node mark (BTCNodeM)
    MOVE.W      D4,0x16(A4)                     | update index mark (BTCIndexM)
    MOVEQ.L     #0x20,D0                        | result = BTnotfound
    BRA.B       BTREC_EXIT                      | exit ->
| GRGotIt: found the record
BTREC_FOUND:
    MOVE.W      D4,D1                           | record index
    MOVEA.L     A3,A1                           | A1 = node buffer
    JSR         LOCREC(PC)                      | locate key and data record
    MOVE.L      D3,0x12(A4)                     | update node mark (BTCNodeM)
    MOVE.W      D4,0x16(A4)                     | update index mark (BTCIndexM)
    CLR.W       D0                              | result = noErr
| GRExit
BTREC_EXIT:
    MOVEM.L     D0-D1/A0-A1,-(A6)               | save return values
    BSR.B       GR_RELNODE                      | GR_RELNODE: release node buffer
    MOVEM.L     (A6)+,D0-D1/A0-A1               | restore return values
    MOVE.L      D3,D2                           | hint = node number
    BSR.W       BT_CLEANUP                      | BTCleanUp: release BTCB
    MOVEM.L     (A6)+,D3-D5/A2-A4               | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from BTGetRecord
| GR_GETNODE: release current node and get node D3
GR_GETNODE:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    BSR.B       GR_RELNODE                      | release current node
    MOVEQ.L     #0x0,D1                         | no GetBlock options
    MOVE.L      D3,D2                           | node number
    JSR         GETNODE(PC)                     | read node into cache
    BNE.B       GRGETNODE_EXIT                  | error ->
    MOVEA.L     A0,A3                           | A3 = new node buffer
GRGETNODE_EXIT:
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from GR_GETNODE
| GR_RELNODE: release current node buffer
GR_RELNODE:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEQ.L     #0x0,D1                         | no RelBlock options
    MOVEA.L     A3,A0                           | A0 = node buffer
    JSR         RELNODE(PC)                     | release the node
    SUBA.L      A3,A3                           | A3 = nil (no buffer held)
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from GR_RELNODE
| Called by: EXTENDFILE_LOOP, CC_ADD_REC, CC_CLR_THD_LOOP, MC_INSERT_DST, CMRENAMECN
BTINSERT:
    MOVE.L      (0x740).W,-(A7)                 | HFS vector: BTInsert trampoline
    RTS                                         | dispatch via vector
VBTINSERT:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1/D3-D7/A0-A4,-(A6)            | save regs
    JSR         LOCBTCB(PC)                     | locate BTCB -> A4
    MOVE.L      A1,D7                           | D7 = ptr to data record
    MOVE.W      D1,D6                           | D6 = data record size
    MOVE.L      A0,D5                           | D5 = ptr to key
| ensure file space for worst-case split
    MOVEQ.L     #0x1,D3                         | required nodes =
    ADD.W       0x18(A4),D3                     | tree depth + 1 (BTCDepth)
    CMP.L       0x32(A4),D3                     | enough free nodes? (BTCFree)
    BLE.B       BTINS_INIT                      | yes ->
BTINS_EXTEND_RETRY:
    JSR         EXTBTFILE(PC)                   | extend B-tree file
    BNE.W       BTINS_EXIT                      | error ->
    CMP.L       0x32(A4),D3                     | enough space now?
    BGT.B       BTINS_EXTEND_RETRY              | no, extend again ->
| BIInit: setup and build B-tree record
BTINS_INIT:
    MOVE.W      0x2(A4),D0                      | file refnum (BTCRefNum)
    BSR.W       BT_SETUP                        | BT_SETUP: common initialization
    MOVEM.L     D6-D7,-(A6)                     | save input record size and ptr
    MOVEQ.L     #0x0,D4                         | no parent node buffer
    SUBA.L      A2,A2                           | no left node buffer
    SUBA.L      A3,A3                           | no right node buffer
    CLR.L       0x12(A4)                        | invalidate node mark (BTCNodeM)
| build B-tree record: key + junk data in BTVRecord
    MOVEA.L     0xC(A4),A1                      | A1 = BTCVarPtr
    LEA.L       0x30(A1),A1                     | offset to BTVRecord buffer
    MOVEA.L     D5,A0                           | source = input key
    MOVEQ.L     #0x0,D0                         | clear for length byte
    MOVE.B      (A0),D0                         | D0 = key length
    ADDQ.L      #0x2,D0                         | include length byte + pad
    LSR.L       #0x1,D0                         | round to word boundary
    LSL.L       #0x1,D0                         | (LSR+LSL = round up to even)
    ADD.W       D0,D6                           | total size = key + data
    _BlockMove                                  | copy key into record buffer
    ADDQ.W      #0x1,D6                         | round total size to even
    LSR.W       #0x1,D6                         | divide by 2
    LSL.W       #0x1,D6                         | multiply by 2
    MOVE.L      A1,D7                           | D7 = ptr to B-tree record
| BISearch: search tree for key
    JSR         TREESEARCH(PC)                  | search for insertion point
    MOVEA.L     A1,A3                           | A3 = right node buffer
    BNE.B       BTINS_CHKERR                    | not found or error ->
    MOVEQ.L     #0x21,D0                        | key already exists (BTexists)
    BRA.W       BTINS_CLEANUP                   | exit ->
| ----------------------------------------------------------
|
| BTINS_CHKERR
|
BTINS_CHKERR:
    CMPI.W      #0x20,D0                        | key not found? (BTnotfound)
    BNE.W       BTINS_CLEANUP                   | no, I/O error ->
    MOVE.L      D2,D3                           | D3 = right node number
    MOVE.W      D1,D5                           | D5 = insert index
| if tree empty, create first leaf node
    TST.W       0x10(A4)                        | tree non-empty? (BTCLevel)
    BGT.B       BTINS_INSERT                    | yes ->
    MOVE.W      0x2(A4),D0                      | file refnum (BTCRefNum)
    JSR         ALLOCNODE(PC)                   | allocate a new node
    BNE.W       BTINS_CLEANUP                   | error ->
    MOVE.L      D1,D3                           | D3 = new node number
    JSR         INITNODE(PC)                    | initialize node -> A0
    BNE.W       BTINS_CLEANUP                   | error ->
    MOVEA.L     A0,A3                           | A3 = new root node
    MOVE.B      #0xFF,0x8(A3)                   | NDType = leaf (0xFF)
    MOVEQ.L     #0x1,D0                         | height = 1
    MOVE.B      D0,0x9(A3)                      | NDNHeight = 1
    MOVE.W      D0,0x18(A4)                     | BTCDepth = 1
    MOVE.L      D3,0x1A(A4)                     | BTCRoot = new node
    MOVE.L      D3,0x22(A4)                     | BTCFNode = new node (first leaf)
    MOVE.L      D3,0x26(A4)                     | BTCLNode = new node (last leaf)
    MOVE.W      #0x1,0x10(A4)                   | BTCLevel = 1
| BIInsert: try simple insert first
BTINS_INSERT:
    MOVEA.L     D7,A0                           | A0 = ptr to record
    MOVE.W      D6,D0                           | D0 = record size
    MOVEA.L     A3,A1                           | A1 = node buffer
    MOVE.W      D5,D1                           | D1 = insert index
    JSR         INSERTREC(PC)                   | try to insert record
    BNE.B       BTINS_TRY_ROTLT                 | didn't fit ->
    TST.W       D5                              | inserted as first record?
    BNE.B       BTINS_INSDONE                   | no, insert done ->
    BSET        #0x6,(A4)                       | set BTCKeyUpd: index key changed
    BRA.B       BTINS_INSDONE                   | insert done ->
| BIRotate: try rotation into left sibling
BTINS_TRY_ROTLT:
    MOVEA.L     A3,A0                           | A0 = right node
    JSR         GETLTSIB(PC)                    | get left sibling
    BNE.W       BTINS_CLEANUP                   | error ->
    TST.L       D1                              | has left sibling?
    BEQ.B       BTINS_DOSPLIT                   | no, must split ->
    MOVE.L      D1,D2                           | D2 = left node number
    MOVEA.L     A1,A2                           | A2 = left node buffer
    MOVEA.L     D7,A0                           | ptr to record
    MOVE.W      D6,D0                           | record size
    MOVE.W      D5,D1                           | insert index
    JSR         ROTATELT(PC)                    | try RotateLT
    BNE.B       BTINS_DOSPLIT                   | rotation failed ->
    BRA.B       BTINS_KEYUPD                    | rotation ok ->
| BISplit: rotation failed, must split the node
BTINS_DOSPLIT:
    MOVEA.L     D7,A0                           | ptr to record
    MOVE.W      D6,D0                           | record size
    MOVE.W      D5,D1                           | insert index
    JSR         SPLITLT(PC)                     | split left
    BEQ.B       BTINS_NEWIREC                   | ok ->
    MOVEQ.L     #0x23,D0                        | result = BTnoFit
    BRA.W       BTINS_CLEANUP                   | exit ->
BTINS_NEWIREC:
    BSET        #0x5,(A4)                       | set BTCNewIRec: need new index record
BTINS_KEYUPD:
    BSET        #0x6,(A4)                       | set BTCKeyUpd: key update required
    MOVE.W      D1,D5                           | D5 = new record index
    MOVEA.L     A2,A0                           | mark left node dirty
    JSR         MARKBLOCK(PC)                   | mark left node buffer dirty
| BIInsDone: insert completed
BTINS_INSDONE:
    MOVEA.L     A3,A0                           | mark right node dirty
    JSR         MARKBLOCK(PC)                   | mark right node buffer dirty
    CMPI.B      #0xFF,0x8(A1)                   | leaf level? (NDType=0xFF)
    BNE.B       BTINS_CKDONE                    | no ->
    MOVEM.L     (A6),D0/A0                      | get input record ptr and size
    JSR         UPDDREC(PC)                     | replace junk data with real data
    ADDQ.L      #0x1,0x1E(A4)                   | bump leaf record count (BTCNRecs)
    MOVE.W      D5,0x16(A4)                     | save index marker (BTCIndexM)
    MOVE.L      D3,D0                           | assume right node number
    CMPA.L      A3,A1                           | record in right node?
    BEQ.B       BTINS_SAVEMARK                  | yes ->
    MOVE.L      D2,D0                           | no, use left node number
BTINS_SAVEMARK:
    MOVE.L      D0,0x12(A4)                     | save node marker (BTCNodeM)
| BICkDone: check if key update or new index needed
BTINS_CKDONE:
    BTST        #0x6,(A4)                       | key update required? (BTCKeyUpd)
    BNE.B       BTINS_NXTLEV                    | yes, go to next level ->
    BTST        #0x5,(A4)                       | new index record needed? (BTCNewIRec)
    BEQ.W       BTINS_DONE                      | no, all done ->
| BINxtLev: move to next level up
BTINS_NXTLEV:
    SUBQ.W      #0x1,0x10(A4)                   | bump to next level up (BTCLevel)
    BEQ.W       BTINS_NEWROOT                   | reached root ->
    MOVE.W      0x10(A4),D0                     | current level
    JSR         LOCTPR(PC)                      | locate TPR for this level
    MOVE.W      0x4(A0),D5                      | D5 = parent record index (TPRRIndx)
    MOVE.L      (A0),D3                         | D3 = parent node number
    MOVE.L      D2,-(A6)                        | save left node number
    MOVEQ.L     #0x0,D1                         | no options
    MOVE.L      D3,D2                           | D2 = parent node number
    JSR         GETNODE(PC)                     | read parent node into cache
    BNE.W       BTINS_CLEANUP                   | error ->
    MOVE.L      A0,D4                           | D4 = parent node buffer
    MOVE.L      (A6)+,D2                        | restore left node number
| BIUpdKey: update parent index key if needed
    BTST        #0x6,(A4)                       | key update required? (BTCKeyUpd)
    BEQ.B       BTINS_RELRIGHT                  | no ->
    MOVE.W      D5,D0                           | locate parent index record
    MOVEA.L     D4,A1                           | A1 = parent node
    JSR         GETRECA(PC)                     | get parent record -> A0
    MOVE.L      A0,-(A7)                        | save ptr to parent record
    MOVEA.L     A3,A1                           | A1 = right child node
    CLR.W       D0                              | record 0 (first key)
    JSR         GETRECA(PC)                     | get first key in child
    MOVEA.L     (A7)+,A1                        | A1 = parent index record
    JSR         UPDIKEY(PC)                     | update parent key from child
    MOVEA.L     D4,A0                           | mark parent dirty
    JSR         MARKBLOCK(PC)                   | mark parent node dirty
    TST.W       D5                              | update to 1st key in node?
    BEQ.B       BTINS_RELRIGHT                  | yes, keep BTCKeyUpd set ->
    BCLR        #0x6,(A4)                       | clear BTCKeyUpd for next level
| BIRelRight: release right, promote parent
BTINS_RELRIGHT:
    MOVEQ.L     #0x0,D1                         | release without write
    MOVEA.L     A3,A0                           | A0 = right node
    JSR         RELNODE(PC)                     | release right node
    MOVEA.L     D4,A3                           | parent becomes new right node
    MOVEQ.L     #0x0,D4                         | no parent buffer
| BINewRec: build new index record if split occurred
    BTST        #0x5,(A4)                       | new index record needed? (BTCNewIRec)
    BEQ.B       BTINS_RELLEFT                   | no ->
    MOVEA.L     A2,A1                           | left node
    MOVE.L      D2,D0                           | left node number
    JSR         BUILDIREC(PC)                   | build index record (BuildIRec)
| BIRelLeft: release left node
BTINS_RELLEFT:
    MOVEQ.L     #0x0,D1                         | release without write
    MOVEA.L     A2,A0                           | A0 = left node
    JSR         RELNODE(PC)                     | release left node
    SUBA.L      A2,A2                           | A2 = nil
| BIBldIRec: build index record for new level
    BTST        #0x5,(A4)                       | new index record needed? (BTCNewIRec)
    BEQ.W       BTINS_CKDONE                    | no, check done ->
    MOVEA.L     0xC(A4),A0                      | A0 = BTCVarPtr
    LEA.L       0x30(A0),A0                     | offset to BTVRecord
    MOVE.L      A0,D7                           | D7 = ptr to record buffer
    JSR         GETMAXKEY(PC)                   | get max key size
    ADDQ.W      #0x4,D0                         | add node pointer size
    MOVE.W      D0,D6                           | D6 = index record size
    BCLR        #0x5,(A4)                       | clear BTCNewIRec
    BRA.W       BTINS_INSERT                    | insert index record ->
| BINewRoot: create new root (tree grew taller)
BTINS_NEWROOT:
    BTST        #0x5,(A4)                       | split propagated to root?
    BEQ.B       BTINS_DONE                      | no, done ->
    MOVE.W      0x2(A4),D0                      | file refnum (BTCRefNum)
    JSR         ALLOCNODE(PC)                   | allocate new root node
    BNE.B       BTINS_CLEANUP                   | error ->
    MOVE.L      D1,D3                           | D3 = new root node number
    MOVE.L      D3,D1                           | D1 for InitNode
    JSR         INITNODE(PC)                    | initialize new root
    BNE.B       BTINS_CLEANUP                   | error ->
    MOVE.L      A0,D4                           | D4 = new root buffer
    CLR.B       0x8(A0)                         | NDType = index node (0)
    MOVEQ.L     #0x1,D0                         | new height =
    ADD.W       0x18(A4),D0                     | current depth + 1
    MOVE.B      D0,0x9(A0)                      | NDNHeight
| insert left child index record into new root
    MOVEA.L     A2,A1                           | left child node
    MOVE.L      D2,D0                           | left node number
    JSR         BUILDIREC(PC)                   | build index record (BuildIRec)
    JSR         GETMAXKEY(PC)                   | get max key size
    ADDQ.W      #0x4,D0                         | add node pointer
    MOVEA.L     0xC(A4),A0                      | A0 = BTCVarPtr
    LEA.L       0x30(A0),A0                     | BTVRecord buffer
    MOVEA.L     D4,A1                           | A1 = new root node
    CLR.W       D1                              | insert at index 0
    JSR         INSERTREC(PC)                   | insert left child record
| insert right child index record into new root
    MOVE.W      #0x1,D0                         | level 1
    JSR         LOCTPR(PC)                      | get TPR for level 1
    MOVE.L      (A0),D0                         | right child node number
    MOVEA.L     A3,A1                           | right child node
    JSR         BUILDIREC(PC)                   | build index record
    JSR         GETMAXKEY(PC)                   | get max key size
    ADDQ.W      #0x4,D0                         | add node pointer
    MOVEA.L     0xC(A4),A0                      | BTVRecord buffer
    LEA.L       0x30(A0),A0                     | offset to record
    MOVEA.L     D4,A1                           | A1 = new root node
    MOVE.W      #0x1,D1                         | insert at index 1
    JSR         INSERTREC(PC)                   | insert right child record
    MOVEA.L     D4,A0                           | mark new root dirty
    JSR         MARKBLOCK(PC)                   | mark new root dirty
    ADDQ.W      #0x1,0x18(A4)                   | increment tree depth (BTCDepth)
    MOVE.L      D3,0x1A(A4)                     | new root node (BTCRoot)
| BIDone: insert complete
BTINS_DONE:
    BSET        #0x7,(A4)                       | mark BTCB dirty (BTCDirty)
    CLR.W       D0                              | result = noErr
| BICleanup: release all nodes and exit
| Called by: BTINS_CHKERR, BTINS_NEWROOT, BTINS_INIT, BTINS_TRY_ROTLT, BTINS_DOSPLIT (and 1 more)
BTINS_CLEANUP:
    MOVE.W      D0,-(A6)                        | save result code
    MOVEA.L     A2,A0                           | release left node
    MOVEQ.L     #0x0,D1                         | no write
    JSR         RELNODE(PC)                     | release it
    MOVEA.L     A3,A0                           | release right node
    JSR         RELNODE(PC)                     | release it
    MOVEA.L     D4,A0                           | release parent node
    JSR         RELNODE(PC)                     | release it
    MOVE.W      (A6)+,D0                        | restore result code
    MOVE.L      0x12(A4),D2                     | D2 = hint (BTCNodeM)
    CLR.L       0x12(A4)                        | invalidate node mark
    BSR.W       BT_CLEANUP                      | BTCleanUp: release BTCB
    ADDQ.L      #0x8,A6                         | pop saved D6-D7
BTINS_EXIT:
    MOVEM.L     (A6)+,D1/D3-D7/A0-A4            | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from BTInsert
BTOPEN:
    MOVE.L      (0x744).W,-(A7)                 | HFS vector: BTOpen trampoline
    RTS                                         | dispatch via vector
VBTOPEN:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1-D5/A0-A4,-(A6)               | save regs
    MOVE.W      D0,D3                           | D3 = file refnum
    MOVE.L      A0,D4                           | D4 = key compare proc ptr
    MOVE.L      A1,D5                           | D5 = cache queue ptr
| allocate BTCB (B-tree control block)
    MOVEQ.L     #0x36,D0                        | BTCB size = 54 bytes
    _NewPtrSysClear                             | allocate zeroed system memory
    BNE.W       BTOPEN_EXIT                     | error ->
    MOVEA.L     A0,A4                           | A4 = BTCB pointer
    MOVEA.L     (FCBSPtr).W,A3                  | A3 = FCB array base
    MOVE.L      A4,0x22(A3,D3.W)                | store BTCB ptr in FCB extension
    MOVE.W      D3,0x2(A4)                      | BTCRefNum = file refnum
    MOVE.L      D4,0x4(A4)                      | BTCKeyCR = key compare routine
    MOVE.L      D5,0x8(A4)                      | BTCCQPtr = cache queue ptr
| read header node (node 0) from disk
    MOVE.W      D3,D0                           | file refnum
    MOVEA.L     D5,A1                           | cache queue
    MOVEQ.L     #0x0,D1                         | no options
    MOVEQ.L     #0x0,D2                         | block 0 (header node)
    JSR         GETBLOCK(PC)                    | read header block
    BNE.B       BTOPEN_EXIT                     | error ->
    MOVEA.L     A0,A2                           | A2 = header node buffer
| BOValBTH: validate B-tree header
    LEA.L       0xE(A2),A0                      | A0 = BTH (after node descriptor)
    MOVE.W      0x12(A0),D0                     | node size (bthNodeSize)
    BEQ.B       BTOPEN_BADHDR                   | zero is invalid ->
    MOVE.W      D0,D1                           | check power of 2 alignment
    ANDI.W      #0x1FF,D1                       | must be multiple of 512
    BNE.B       BTOPEN_BADHDR                   | not aligned ->
    MOVE.L      0xC(A3,D3.W),D2                 | PEOF from FCB
    DIVU.W      D0,D2                           | total nodes = PEOF / nodeSize
    SWAP.W      D2                              | discard remainder
    CLR.W       D2                              | D2 = total node count
    SWAP.W      D2                              | (quotient in low word)
    CMP.L       0x16(A0),D2                     | matches bthNNodes?
    BNE.B       BTOPEN_BADHDR                   | no ->
    CMP.L       0x1A(A0),D2                     | free nodes <= total?
    BCS.B       BTOPEN_BADHDR                   | no ->
    SUBQ.L      #0x1,D2                         | max valid node number
    CMPI.B      #0x8,(A0)                       | depth <= 8?
    BHI.B       BTOPEN_BADHDR                   | no ->
    CMP.L       0x2(A0),D2                      | root within range?
    BCS.B       BTOPEN_BADHDR                   | no ->
    CMP.L       0xA(A0),D2                      | first leaf within range?
    BCS.B       BTOPEN_BADHDR                   | no ->
    CMP.L       0xE(A0),D2                      | last leaf within range?
    BCC.B       BTOPEN_CPYBTH                   | yes, header valid ->
| Called by: VBTOPEN
BTOPEN_BADHDR:
    MOVEQ.L     #0x25,D0                        | result = BTbadHdr
    BRA.B       BTOPEN_RELBLK                   | exit ->
| ----------------------------------------------------------
|
| BTOPEN_CPYBTH
|
| BOCpyBTH: copy BTH into BTCB
BTOPEN_CPYBTH:
    MOVE.W      #0x1D,D0                        | LenMemBTH-1 = 29 ($1D)
    LEA.L       0xE(A2),A0                      | source = BTH in node
    LEA.L       0x18(A4),A1                     | dest = BTCB header fields
BTOPEN_CPYLOOP:
    MOVE.B      (A0)+,(A1)+                     | copy BTH to BTCB
    DBF.W       D0,BTOPEN_CPYLOOP               | loop for all bytes
    CLR.W       D0                              | result = noErr
BTOPEN_RELBLK:
    MOVE.W      D0,-(A6)                        | save result code
    MOVEA.L     D5,A1                           | cache queue ptr
    MOVEQ.L     #0x0,D1                         | no options
    MOVEA.L     A2,A0                           | header node buffer
    JSR         RELBLOCK(PC)                    | release header block
    BEQ.B       BTOPEN_RESULT                   | ok ->
    MOVE.W      D0,(A6)                         | override with RelBlock error
BTOPEN_RESULT:
    MOVE.W      (A6)+,D0                        | restore result code
BTOPEN_EXIT:
    MOVEM.L     (A6)+,D1-D5/A0-A4               | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from BTOpen
| Called by: MOUNTVOL_OK_9, DEALLOCFILE_NEXT, TRUNCATEFILE_RELEASE_EXTENT, VXFSEARCH, XFSEARCH_NO_2 (and 1 more)
BTSEARCH:
    MOVE.L      (0x748).W,-(A7)                 | HFS vector: BTSearch trampoline
    RTS                                         | dispatch via vector
VBTSEARCH:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D3-D7/A2-A4,-(A6)               | save regs
    BSR.W       BT_SETUP                        | BT_SETUP: find BTCB -> A4
    MOVEA.L     A0,A3                           | A3 = search key
    SUBA.L      A2,A2                           | no node buffer yet
| BSHint: try hint-based shortcut first
    TST.L       D2                              | hint node number provided?
    BEQ.B       BTSRCH_TREE                     | no, do full search ->
    MOVEQ.L     #0x0,D1                         | no options
    JSR         GETNODE(PC)                     | get hint node into cache
    BNE.B       BTSRCH_RELNODE                  | error ->
    MOVEA.L     A0,A2                           | A2 = hint node buffer
    CMPI.B      #0xFF,0x8(A0)                   | leaf node? (NDType=0xFF)
    BNE.B       BTSRCH_RELHINT                  | no, hint invalid ->
    TST.W       0xA(A0)                         | any records? (NDNRecs)
    BLE.B       BTSRCH_RELHINT                  | no, hint invalid ->
    MOVEA.L     A3,A0                           | A0 = search key
    MOVEA.L     A2,A1                           | A1 = hint node
    JSR         SEARCHNODE(PC)                  | search within hint node
    BEQ.B       BTSRCH_FOUND                    | found it ->
| hint failed, release and do full search
BTSRCH_RELHINT:
    MOVEA.L     A2,A0                           | A0 = hint node
    MOVEQ.L     #0x0,D1                         | no options
    JSR         RELNODE(PC)                     | release hint node
    BNE.B       BTSRCH_RELNODE                  | error ->
| BSSearch: full tree search
BTSRCH_TREE:
    MOVEA.L     A3,A0                           | A0 = search key
    JSR         TREESEARCH(PC)                  | search from root to leaf
    MOVEA.L     A1,A2                           | A2 = found node
    BEQ.B       BTSRCH_FOUND                    | found ->
    CMPI.W      #0x20,D0                        | BTnotfound?
    BNE.B       BTSEARCH_CLEANUP                | no, I/O error ->
| BSGotIt: found or not-found with valid position
BTSRCH_FOUND:
    MOVE.W      D1,D5                           | D5 = record index
    MOVE.W      D0,-(A6)                        | save result (0=found, 0x20=not found)
    MOVE.L      D2,0x12(A4)                     | save node mark (BTCNodeM)
    MOVE.W      D5,0x16(A4)                     | save index mark (BTCIndexM)
    TST.W       (A6)                            | found?
    BNE.B       BTSRCH_RELNODE                  | no (BTnotfound), exit ->
    MOVE.W      D5,D0                           | record index for LocRec
    MOVEA.L     A2,A1                           | A1 = found node
    JSR         LOCREC(PC)                      | locate key and data record
| BSExit: release node and return
BTSRCH_RELNODE:
    MOVEM.L     D1-D2/A0-A1,-(A6)               | save return values
    MOVEA.L     A2,A0                           | A0 = node buffer
    MOVEQ.L     #0x0,D1                         | release without write
    JSR         RELNODE(PC)                     | release node buffer
    MOVEM.L     (A6)+,D1-D2/A0-A1               | restore return values
    MOVE.W      (A6)+,D0                        | restore result code
BTSEARCH_CLEANUP:
    BSR.B       BT_CLEANUP                      | BTCleanUp: release BTCB
    MOVEM.L     (A6)+,D3-D7/A2-A4               | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from BTSearch
| Called by: MC_UPD_DEST, XFSEARCH_LOOP_3, CC_UPD_PAR, DC_UPD_PAR, MC_UPD_SRC (and 3 more)
BTUPDATE:
    MOVE.L      (0x74C).W,-(A7)                 | HFS vector: BTUpdate trampoline
    RTS                                         | dispatch via vector
VBTUPDATE:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1/A0-A1/A4,-(A6)               | save regs
    JSR         LOCBTCB(PC)                     | locate BTCB -> A4
    MOVEQ.L     #0x2,D1                         | D1 = GBexist (force read)
    JSR         GETNODE(PC)                     | get node into cache
    BNE.B       BTUPD_EXIT                      | error ->
    MOVEQ.L     #0x4,D1                         | D1 = RBdirty (mark dirty)
    JSR         RELNODE(PC)                     | release node (dirty)
    BNE.B       BTUPD_EXIT                      | error ->
    CLR.W       D0                              | result = noErr
BTUPD_EXIT:
    MOVEM.L     (A6)+,D1/A0-A1/A4               | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from BTUpdate
| ----------------------------------------------------------
|
| BT_CLEANUP
|
| BTCleanUp: deallocate BTV vars from A6 stack
BT_CLEANUP:
    MOVE.L      D0,-(A7)                        | save result code
    BSR.B       GETBTVARSIZE                    | D0 = BTVar size
    ADDA.L      D0,A6                           | deallocate BTV vars from A6
    CLR.L       0xC(A4)                         | clear BTCVarPtr
    MOVE.L      (A7)+,D0                        | restore result code
    RTS                                         | return from BTCleanUp
| BT_SETUP: allocate BTV vars, locate BTCB
BT_SETUP:
    MOVE.L      D0,-(A7)                        | save file refnum
    JSR         LOCBTCB(PC)                     | locate BTCB -> A4
    BSR.B       GETBTVARSIZE                    | D0 = BTVar size
    SUBA.L      D0,A6                           | allocate BTV vars on A6 stack
    MOVE.L      A6,0xC(A4)                      | BTCVarPtr = A6
    BCLR        #0x5,(A4)                       | clear BTCNewIRec
    BCLR        #0x4,(A4)                       | clear BTCDelIRec
    BCLR        #0x6,(A4)                       | clear BTCKeyUpd
    MOVE.L      (A7)+,D0                        | restore file refnum
    RTS                                         | return from BT_SETUP
| GetBTVarSize: calculate B-tree variable block size
GETBTVARSIZE:
    JSR         GETMAXKEY(PC)                   | D0 = max key length
    ADDI.W      #0x34,D0                        | add BTVRecord+TPR overhead
    RTS                                         | return size in D0
BTALLOC:                                        | Apple source module (MacSEROM.lst)
ALLOCNODE:
    MOVE.L      (0x758).W,-(A7)                 | HFS vector: AllocNode trampoline
    RTS                                         | dispatch via vector
VALLOCNODE:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D2-D4/A2-A3,-(A6)               | save regs
    MOVEQ.L     #0x0,D4                         | D4 = bit offset into bitmap
    SUBA.L      A2,A2                           | no map node buffer yet
| ANGetMap: get next map record
ALLOC_GETMAP:
    BSR.W       GET_MAP                         | get map record -> A1, size -> D1
    BEQ.B       ALLOC_SEARCH                    | ok ->
    CMPI.W      #0x20,D0                        | BTnotfound (no more map records)?
    BNE.B       ALLOC_EXIT                      | no, I/O error ->
    MOVEQ.L     #0x22,D0                        | result = BTnospace
    BRA.B       ALLOC_EXIT                      | exit ->
| ANSearch: scan map record for a free node (zero bit)
ALLOC_SEARCH:
    MOVE.W      D1,D2                           | D2 = map record size
    LSR.W       #0x2,D2                         | D2 = longword count
    SUBQ.W      #0x1,D2                         | adjust for DBF
    MOVEA.L     A1,A0                           | A0 = map record data
ALLOC_SCANLW:
    MOVE.L      (A0)+,D0                        | read longword from bitmap
    CMPI.L      #0xFFFFFFFF,D0                  | all bits set (all allocated)?
    BNE.B       ALLOC_FOUNDLW                   | no, has a free bit ->
    DBF.W       D2,ALLOC_SCANLW                 | loop for all longwords
    EXT.L       D1                              | map record size to long
    LSL.L       #0x3,D1                         | bits = bytes * 8
    ADD.L       D1,D4                           | advance bit offset
    BRA.B       ALLOC_GETMAP                    | try next map record ->
| ANFound: found a longword with a free bit
ALLOC_FOUNDLW:
    MOVE.W      #0x1F,D2                        | scan from bit 31 down
ALLOC_SCANBIT:
    BTST        D2,D0                           | bit clear (free)?
    BEQ.B       ALLOC_FOUNDBIT                  | yes, found free node ->
    DBF.W       D2,ALLOC_SCANBIT                | try next bit
ALLOC_FOUNDBIT:
    BSET        D2,D0                           | mark node as allocated
    MOVE.L      D0,D3                           | save updated longword
    LEA.L       -0x4(A0),A0                     | back up to longword start
    MOVEA.L     A0,A3                           | save longword address
    SUBA.L      A1,A0                           | byte offset in map record
    MOVE.L      A0,D1                           | D1 = byte offset
    LSL.L       #0x3,D1                         | D1 = bit offset in record
    ADDI.L      #0x1F,D1                        | add max bit position
    EXT.L       D2                              | sign-extend bit index
    SUB.L       D2,D1                           | D1 = actual bit position
    ADD.L       D4,D1                           | D1 = node number (absolute)
| check node number within valid range
    MOVE.L      0x2E(A4),D0                     | total nodes (BTCNNodes)
    CMP.L       D1,D0                           | node within range?
    BGT.B       ALLOC_COMMIT                    | yes ->
    BSR.W       REL_MAP                         | release map node
    MOVEQ.L     #0x22,D0                        | result = BTnospace
    BRA.B       ALLOC_EXIT                      | exit ->
| ANMark: mark node allocated in bitmap
ALLOC_COMMIT:
    MOVE.L      D3,(A3)                         | write updated bitmap longword
    MOVEA.L     A2,A0                           | A0 = map node buffer
    JSR         MARKBLOCK(PC)                   | mark map node dirty
    SUBQ.L      #0x1,0x32(A4)                   | decrement free count (BTCFree)
    BSET        #0x7,(A4)                       | mark BTCB dirty (BTCDirty)
    CLR.W       D0                              | result = noErr
    BSR.W       REL_MAP                         | release map node
ALLOC_EXIT:
    MOVEM.L     (A6)+,D2-D4/A2-A3               | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from AllocNode
EXTBTFILE:
    MOVE.L      (0x760).W,-(A7)                 | HFS vector: ExtBTFile trampoline
    RTS                                         | dispatch via vector
VEXTBTFILE:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D2-D6/A2,-(A6)                  | save regs
    MOVE.W      0x2(A4),D1                      | D1 = B-tree file refnum (BTCRefNum)
    MOVEA.L     (FCBSPtr).W,A1                  | A1 = FCB array base
    MOVEA.L     0x14(A1,D1.W),A2                | A2 = VCB pointer (FCBVPtr)
    MOVEQ.L     #0x0,D3                         | no special options
    MOVE.L      0x1E(A1,D1.W),D4                | D4 = clump size (FCBClmpSize)
    JSR         EXTENDFILE(PC)                  | extend the B-tree file
    BEQ.B       EXTBT_CALRANGE                  | ok ->
    CMPI.W      #0xFFDE,D0                      | disk full? (dskFulErr)
    BNE.W       EXTBT_EXIT                      | no, other error ->
    TST.L       D6                              | got any space at all?
    BEQ.W       EXTBT_EXIT                      | no ->
| EFCalRange: calculate node number range for new space
EXTBT_CALRANGE:
    MOVE.L      0x2E(A4),D3                     | D3 = old total nodes (BTCNNodes)
    MOVE.L      D3,D4                           | D4 = first new map node
    MOVE.L      0xC(A1,D1.W),D5                 | D5 = new PEOF from FCB
    DIVU.W      0x2A(A4),D5                     | total nodes = PEOF / nodeSize
    SWAP.W      D5                              | discard remainder
    CLR.W       D5                              | D5 = new total node count
    SWAP.W      D5                              | (quotient in low word)
    MOVE.L      D5,0x2E(A4)                     | update BTCNNodes
    SUBQ.L      #0x1,D5                         | D5 = last new node number
    MOVE.L      D5,D6                           | D6 = last new node
    SUBA.L      A2,A2                           | no map node buffer yet
| EFScanMap: find map record covering new nodes
EXTBT_SCANMAP:
    BSR.W       GET_MAP                         | get next map record
    BNE.W       EXTBT_EXIT                      | error ->
    EXT.L       D1                              | map record size to long
    LSL.L       #0x3,D1                         | bits = bytes * 8
    SUB.L       D1,D3                           | advance past this map's range
    SUB.L       D1,D5                           | adjust last node offset
    BGE.B       EXTBT_MARKMAP                   | new nodes fit in next map ->
    SUBQ.L      #0x1,D4                         | map node itself uses one node
    BRA.B       EXTBT_UPDFREE                   | skip to finish ->
| EFMarkMap: mark map node in existing map, then create new map node
EXTBT_MARKMAP:
    TST.L       (A2)                            | end of map chain?
    BNE.B       EXTBT_SCANMAP                   | no, keep scanning ->
    MOVE.L      D4,(A2)                         | link to new map node
    TST.L       D3                              | new map starts past current map?
    BGE.B       EXTBT_INITMAP                   | yes ->
| mark new map node as allocated in current map
    ADD.L       D1,D3                           | D3 = bit offset within map
    DIVU.W      #0x8,D3                         | byte/bit within map record
    MOVE.W      D3,D0                           | D0 = byte offset
    CLR.W       D3                              | D3 = bit-within-byte (remainder)
    SWAP.W      D3                              | move remainder to low word
    MOVEQ.L     #0x7,D1                         | bit index = 7 - remainder
    SUB.L       D3,D1                           | (big-endian bit ordering)
    BSET        D1,0x0(A1,D0.W)                 | mark node as allocated
    MOVEQ.L     #-0x1,D3                        | flag: already marked
EXTBT_INITMAP:
    MOVEA.L     A2,A0                           | mark current map node dirty
    JSR         MARKBLOCK(PC)                   | mark it dirty
    BSR.W       REL_MAP                         | release current map node
    BNE.B       EXTBT_EXIT                      | error ->
| EFInitMap: create new map node
    MOVE.L      D4,D1                           | new map node number
    JSR         INITNODE(PC)                    | initialize node -> A0
    BNE.B       EXTBT_EXIT                      | error ->
    MOVEA.L     A0,A2                           | A2 = new map node
    MOVE.B      #0x2,0x8(A2)                    | NDType = map node (2)
    MOVE.W      #0x1,0xA(A2)                    | NDNRecs = 1 (one map record)
    MOVE.W      0x2A(A4),D1                     | D1 = node size (BTCNodeSize)
    MOVEQ.L     #-0x12,D0                       | map record size = nodeSize - 18
    ADD.W       D1,D0                           | (subtract ND + overhead)
    LSR.W       #0x2,D0                         | round to longword boundary
    LSL.W       #0x2,D0                         | (LSR+LSL = round down to 4)
    ADDI.W      #0xE,D0                         | add node descriptor offset
    MOVE.W      D0,-0x4(A2,D1.W)                | store record offset
    TST.L       D3                              | need to mark map node itself?
    BLT.B       EXTBT_MARKDIRTY                 | already marked ->
    MOVE.B      #0x80,0xE(A2)                   | mark node 0 as allocated (bit 7)
EXTBT_MARKDIRTY:
    MOVEA.L     A2,A0                           | mark new map node dirty
    JSR         MARKBLOCK(PC)                   | mark it dirty
| EFFinish: update free count and flush
EXTBT_UPDFREE:
    SUB.L       D4,D6                           | D6 = new free nodes (minus map)
    ADD.L       D6,0x32(A4)                     | add to BTCFree
    BSET        #0x7,(A4)                       | mark BTCB dirty (BTCDirty)
    CLR.B       D0                              | result = noErr
    BSR.W       REL_MAP                         | release map node if held
    ST.B        (SysCRefCnt).W                  | flag system cache modified
    BSR.W       UPDALTMDB                       | update alternate MDB
| Called by: VEXTBTFILE, EXTBT_INITMAP, EXTBT_SCANMAP
EXTBT_EXIT:
    MOVEM.L     (A6)+,D2-D6/A2                  | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from ExtBTFile
FREENODE:
    MOVE.L      (0x75C).W,-(A7)                 | HFS vector: FreeNode trampoline
    RTS                                         | dispatch via vector
VFREENODE:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D2-D3/A2,-(A6)                  | save regs
    MOVE.L      D1,D3                           | D3 = node number to free
    SUBA.L      A2,A2                           | no map node buffer yet
| FNScanMap: find map record containing this node
FLUSHVOL_CONT:
    BSR.B       GET_MAP                         | get next map record
    BNE.B       FREENODE_EXIT                   | error ->
    EXT.L       D1                              | map record size to long
    LSL.L       #0x3,D1                         | bits = bytes * 8
    SUB.L       D1,D3                           | advance past this map's range
    BGE.B       FLUSHVOL_CONT                   | not in this map ->
| FNClear: clear the bit for this node
    ADD.L       D1,D3                           | D3 = bit offset within map
    DIVU.W      #0x8,D3                         | byte/bit within map
    MOVEQ.L     #0x0,D0                         | clear high word
    MOVE.W      D3,D0                           | D0 = byte offset
    CLR.W       D3                              | D3 = remainder (bit in byte)
    SWAP.W      D3                              | move to low word
    MOVEQ.L     #0x7,D1                         | bit index = 7 - remainder
    SUB.L       D3,D1                           | (big-endian bit ordering)
    BCLR        D1,0x0(A1,D0.W)                 | clear bit (mark node free)
    MOVEA.L     A2,A0                           | mark map node dirty
    JSR         MARKBLOCK(PC)                   | mark it dirty
    ADDQ.L      #0x1,0x32(A4)                   | increment free count (BTCFree)
    BSET        #0x7,(A4)                       | mark BTCB dirty (BTCDirty)
    CLR.B       D0                              | result = noErr
    BSR.B       REL_MAP                         | release map node
FREENODE_EXIT:
    MOVEM.L     (A6)+,D2-D3/A2                  | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from FreeNode
| GetMapRec: get the next map record from bitmap chain
| Returns: A1=map data, D1=map size, A2=map node buffer
GET_MAP:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEQ.L     #0x0,D2                         | default node = header (0)
    MOVE.L      A2,D0                           | previous map node held?
    BEQ.B       GETMAP_GETNODE                  | no, start from header ->
    MOVE.L      (A2),D2                         | D2 = next map node (NDFLink)
    BSR.B       REL_MAP                         | release previous map node
    BNE.B       GETMAP_EXIT                     | error ->
    TST.L       D2                              | end of map chain?
    BNE.B       GETMAP_GETNODE                  | no, get next ->
    MOVEQ.L     #0x20,D0                        | result = BTnotfound (no more maps)
    BRA.B       GETMAP_EXIT                     | exit ->
GETMAP_GETNODE:
    MOVEQ.L     #0x0,D1                         | no options
    JSR         GETNODE(PC)                     | get map node D2 -> A0
    BNE.B       GETMAP_EXIT                     | error ->
    MOVEA.L     A0,A2                           | A2 = map node buffer
    MOVEQ.L     #0x0,D0                         | record 0 (map record)
    CMPI.B      #0x1,0x8(A2)                    | header node? (NDType=1)
    BNE.B       GETMAP_LOCREC                   | no ->
    MOVEQ.L     #0x2,D0                         | record 2 (map record in header)
GETMAP_LOCREC:
    MOVEA.L     A2,A1                           | A1 = map node
    JSR         GETRECA(PC)                     | get map record start -> A0
    MOVE.L      A0,D1                           | save start address
    MOVE.W      0xA(A2),D0                      | NDNRecs (get end offset)
    JSR         GETRECA(PC)                     | get end of last record -> A0
    MOVEA.L     D1,A1                           | A1 = map record data
    SUBA.L      A1,A0                           | A0 = map record size
    MOVE.W      A0,D1                           | D1 = map record size in bytes
    CLR.W       D0                              | result = noErr
GETMAP_EXIT:
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from GetMapRec
| RelMapNode: release map node A2
| Called by: ALLOC_FOUNDBIT, ALLOC_COMMIT, EXTBT_INITMAP, EXTBT_UPDFREE, FLUSHVOL_CONT (and 1 more)
REL_MAP:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1/A0-A1,-(A6)                  | save regs
    MOVEQ.L     #0x0,D1                         | release without write
    MOVEA.L     A2,A0                           | A0 = map node buffer
    JSR         RELNODE(PC)                     | release it
    SUBA.L      A2,A2                           | A2 = nil
    MOVEM.L     (A6)+,D1/A0-A1                  | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from RelMapNode
| UPDALTMDB (Apple's UpdAltMDB, vector JUpdAltMDB of BTAlloc.a): update the
| alternate MDB on disk
UPDALTMDB:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D0-D2/A0-A3/A5,-(A6)            | save regs
    MOVE.W      0x2(A4),D1                      | D1 = B-tree file refnum
    MOVEA.L     (FCBSPtr).W,A5                  | A5 = FCB array base
    LEA.L       0x0(A5,D1.W),A5                 | A5 = FCB for B-tree file
    MOVEA.L     0x14(A5),A2                     | A2 = VCB pointer (FCBVPtr)
    MOVE.W      0x48(A2),D2                     | D2 = drive number (vcbDrvNum)
    JSR         FINDDRIVE(PC)                   | find drive queue entry -> A3
    BNE.B       FLUSHMDB_EXIT                   | drive not found ->
| calculate last block number for alt MDB
    MOVEQ.L     #0x0,D2                         | clear D2
    MOVE.W      0xC(A3),D2                      | D2 = disk size (low word)
    CMPI.W      #0x2,0x6(A3)                    | drive type > 2?
    BGT.B       FLUSHMDB_USESIZE                | yes, use disk size directly ->
    MOVE.W      #0x320,D2                       | default = 800 blocks (400K)
    TST.B       0xC(A3)                         | double-sided?
    BEQ.B       FLUSHMDB_USESIZE                | no ->
    ASL.L       #0x1,D2                         | yes, 1600 blocks (800K)
FLUSHMDB_USESIZE:
    TST.W       0x4(A3)                         | high word of size?
    BEQ.B       FLUSHMDB_GETBLK                 | no ->
    MOVE.L      0xC(A3),D2                      | D2 = full 32-bit disk size
    SWAP.W      D2                              | (swap for correct endian)
FLUSHMDB_GETBLK:
    SUBQ.W      #0x2,D2                         | alt MDB = last block - 1
    MOVE.W      0x4E(A2),D0                     | vcbVRefNum for GetBlock
    MOVEQ.L     #0x1,D1                         | D1 = GBnoRead (write-only)
    MOVEA.L     0x8(A4),A1                      | cache queue ptr (BTCCQPtr)
    JSR         GETBLOCK(PC)                    | get alt MDB block
    BNE.B       FLUSHMDB_EXIT                   | error ->
    MOVEQ.L     #0x2,D1                         | default: release clean
    CMPI.W      #0x4244,(A0)                    | MDB signature? ('BD'=$4244)
    BNE.B       FLUSHMDB_RELBLK                 | no, not a valid MDB ->
| update extent info in alt MDB
    LEA.L       0x92(A0),A3                     | offset for extents file (CNID=4)
    MOVEQ.L     #0x4,D0                         | extents file CNID
    CMP.L       (A5),D0                         | is this the extents file?
    BEQ.B       FLUSHMDB_UPDEXT                 | yes ->
    MOVEQ.L     #0x3,D0                         | catalog file CNID
    CMP.L       (A5),D0                         | is this the catalog file?
    BNE.B       FLUSHMDB_RELBLK                 | no, don't update ->
    LEA.L       0x82(A0),A3                     | offset for catalog file (CNID=3)
FLUSHMDB_UPDEXT:
    MOVE.L      0xC(A5),(A3)+                   | copy PEOF from FCB
    MOVEQ.L     #0x2,D0                         | 3 extent descriptors (12 bytes)
    LEA.L       0x26(A5),A1                     | source = FCB extent record
FLUSHMDB_CPYEXT:
    MOVE.L      (A1)+,(A3)+                     | copy extent descriptor
    DBF.W       D0,FLUSHMDB_CPYEXT              | loop for all 3 extents
    MOVE.L      (Time).W,0x6(A0)                | update MDB modification date
    MOVEQ.L     #0x1,D1                         | D1 = RBdirty (write back)
FLUSHMDB_RELBLK:
    JSR         RELBLOCK(PC)                    | release alt MDB block
FLUSHMDB_EXIT:
    MOVEM.L     (A6)+,D0-D2/A0-A3/A5            | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from UpdateAltMDB
| RotateLT: rotate records from right node to left sibling
BTMAINT1:                                       | Apple source module (MacSEROM.lst)
ROTATELT:
    MOVEM.L     D2-D7/A2-A5,-(A7)               | save regs
    MOVEA.L     A0,A5                           | A5 = ptr to new record
    MOVE.W      D0,D5                           | D5 = new record size
    MOVEA.L     A2,A1                           | get left node size
    JSR         GETNODESIZ(PC)                  | D0 = left node data size
    MOVE.W      D0,D2                           | D2 = left node size
    MOVEA.L     A3,A1                           | get right node size
    JSR         GETNODESIZ(PC)                  | D0 = right node data size
    ADD.W       D2,D0                           | total = left + right
    ADD.W       D5,D0                           | + new record size
    ADDQ.W      #0x2,D0                         | + offset table entry
    LSR.W       #0x1,D0                         | D0 = ideal split point
    MOVE.W      D0,D6                           | D6 = target size for left
    MOVE.W      0xA(A2),D3                      | D3 = left NDNRecs (rotation index)
    MOVE.W      D1,D4                           | D4 = insert index in right
    ADD.W       D3,D4                           | adjust for left's records
    MOVEQ.L     #-0x1,D7                        | D7 = best split point (none yet)
| RLFitLoop
ROTLT_FITLOOP:
    CMP.W       D3,D4                           | at insert point?
    BNE.B       ROTLT_GETREC                    | no, get existing record ->
    ADD.W       D5,D2                           | include new record in left size
    BRA.B       ROTLT_INCLOFF                   | ->
ROTLT_GETREC:
    MOVE.W      D3,D0                           | convert virtual index
    SUB.W       0xA(A2),D0                      | to right node index (- left NDNRecs)
    CMP.W       D4,D3                           | past insert point?
    BLE.B       ROTLT_SKIPADJ                   | no, skip adjustment ->
    SUBQ.W      #0x1,D0                         | adjust for not-yet-inserted record
ROTLT_SKIPADJ:
    JSR         GETRECA(PC)                     | get record size -> D0
    ADD.W       D0,D2                           | include record in left size
ROTLT_INCLOFF:
    ADDQ.W      #0x2,D2                         | + offset table entry
    MOVE.W      0x2A(A4),D1                     | BTCNodeSize
    SUBI.W      #0x10,D1                        | max data size (- ND header - 2)
    CMP.W       D1,D2                           | left node fits?
    BLE.B       ROTLT_CHKRT                     | yes ->
    SWAP.W      D7                              | overflow: try previous fit
    TST.W       D7                              | have previous fit?
    BGE.B       ROTLT_DOROT                     | yes, use it ->
    MOVEQ.L     #-0x1,D0                        | result = won't fit
    BRA.W       ROTLT_EXIT                      | exit ->
| ----------------------------------------------------------
|
| ROTLT_CHKRT
|
ROTLT_CHKRT:
    MOVE.W      D6,D0                           | split point
    LSL.W       #0x1,D0                         | x 2 = total data size
    SUB.W       D2,D0                           | - left size = right size
    CMP.W       D1,D0                           | right node fits?
    BGT.B       ROTLT_CKSPLIT                   | no ->
    MOVE.W      D3,D7                           | save index as current fit
| RLCkSplit: select best fit
ROTLT_CKSPLIT:
    CMP.W       D6,D2                           | reached split point?
    BLT.B       ROTLT_NEXTFIT                   | not yet, keep going ->
    BEQ.B       ROTLT_CHKFIT                    | exact match ->
    SWAP.W      D7                              | past split: try previous fit first
ROTLT_CHKFIT:
    TST.W       D7                              | have a fit?
    BGE.B       ROTLT_DOROT                     | yes, use it ->
    SWAP.W      D7                              | try other candidate
    TST.W       D7                              | have a fit?
    BGE.B       ROTLT_DOROT                     | yes, use it ->
ROTLT_NEXTFIT:
    SWAP.W      D7                              | previous fit = current fit
    MOVE.W      #0xFFFF,D7                      | no current fit
    ADDQ.W      #0x1,D3                         | advance to next virtual index
    MOVE.W      0xA(A2),D1                      | left NDNRecs
    ADD.W       0xA(A3),D1                      | + right NDNRecs = max index
    CMP.W       D1,D3                           | more records?
    BLE.B       ROTLT_FITLOOP                   | yes, keep trying ->
    MOVEQ.L     #-0x1,D0                        | result = won't fit
    BRA.B       ROTLT_EXIT                      | exit ->
| ----------------------------------------------------------
|
| ROTLT_DOROT
|
| RLRotate: we have a fit, do the actual rotation
ROTLT_DOROT:
    MOVE.W      0xA(A2),D3                      | D3 = first record in right node
ROTLT_LOOP:
    CMP.W       D3,D4                           | at insert point?
    BNE.B       ROTLT_ROTREC                    | no, rotate existing record ->
    MOVEA.L     A2,A1                           | left node
    MOVEA.L     A5,A0                           | new record
    MOVE.W      D5,D0                           | new record size
    MOVE.W      0xA(A1),D1                      | insert at end of left (NDNRecs)
    JSR         INSERTREC(PC)                   | insert new record in left node
    BNE.B       ROTLT_FATAL                     | trouble ->
    MOVEA.L     A1,A5                           | save node buffer for new record
    MOVE.W      D1,D5                           | save index for new record
    BRA.B       ROTLT_CHKSPLIT                  | ->
ROTLT_ROTREC:
    MOVEA.L     A2,A0                           | left node (dest)
    MOVEA.L     A3,A1                           | right node (source)
    BSR.W       ROT_RECLT                       | RotRecLT: move 1st rec right->left
    BNE.B       ROTLT_FATAL                     | trouble ->
ROTLT_CHKSPLIT:
    CMP.W       D7,D3                           | reached split index?
    BEQ.B       ROTLT_CHKRT2                    | yes ->
    ADDQ.W      #0x1,D3                         | bump record index
    BRA.B       ROTLT_LOOP                      | rotate another ->
| RLCheckRt: check if new record goes in right node
ROTLT_CHKRT2:
    CMP.W       D7,D4                           | insert index > split index?
    BLE.B       ROTLT_OK                        | no, record already placed ->
    MOVEA.L     A3,A1                           | right node
    MOVEA.L     A5,A0                           | new record
    MOVE.W      D5,D0                           | new record size
    MOVE.W      D4,D1                           | virtual insert index
    SUB.W       D7,D1                           | - split index
    SUBQ.W      #0x1,D1                         | - 1 = right node insert index
    JSR         INSERTREC(PC)                   | insert new record in right node
    BNE.B       ROTLT_FATAL                     | trouble ->
    CLR.W       D0                              | result = ok
    BRA.B       ROTLT_EXIT                      | exit ->
| ----------------------------------------------------------
|
| ROTLT_FATAL
|
ROTLT_FATAL:
    MOVEQ.L     #0x40,D0                        | DS error code 64
    _SysError                                   | fatal: B-tree rotation failed
| RLExit
ROTLT_OK:
    CLR.W       D0                              | result = ok
    MOVEA.L     A5,A1                           | return node buffer
    MOVE.W      D5,D1                           | return index for new record
ROTLT_EXIT:
    MOVEM.L     (A7)+,D2-D7/A2-A5               | restore regs
    TST.W       D0                              | set condition codes
    RTS                                         | return from ROTLT_EXIT
SPLITLT:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D3-D7/A3,-(A6)                  | save regs
    MOVE.L      A0,D7                           | D7 = ptr to new record
    MOVE.W      D0,D6                           | D6 = new record size
    MOVE.W      D1,D5                           | D5 = insert index
    MOVE.W      0x10(A4),D0                     | BTCLevel
    JSR         LOCTPR(PC)                      | locate TPR for current level
    MOVE.L      (A0),D4                         | D4 = right node number (TPRNodeN)
    MOVE.W      0x2(A4),D0                      | BTCRefNum
    JSR         ALLOCNODE(PC)                   | allocate new node
    BNE.B       SPLITLT_EXIT                    | error ->
    MOVE.L      D1,D3                           | D3 = new left node number
    MOVE.L      A2,D0                           | have an existing left node?
    BEQ.B       SPLITLT_INIT                    | no ->
    MOVE.L      D3,(A2)                         | left NDFLink = new node
    MOVEQ.L     #0x4,D1                         | RBdirty
    MOVEA.L     A2,A0                           | left node buffer
    JSR         RELNODE(PC)                     | release old left node
    BNE.B       SPLITLT_EXIT                    | error ->
SPLITLT_INIT:
    MOVE.L      D3,D1                           | new node number
    JSR         INITNODE(PC)                    | get initialized node buffer
    BNE.B       SPLITLT_EXIT                    | error ->
    MOVEA.L     A0,A2                           | A2 = new left node
    MOVE.B      0x8(A3),0x8(A2)                 | copy NDType from right node
    MOVE.L      0x4(A3),0x4(A2)                 | new NDBLink = right's NDBLink
    MOVE.L      D4,(A2)                         | new NDFLink = right node number
    MOVE.L      D3,0x4(A3)                      | right NDBLink = new left node
    MOVEQ.L     #0x1,D0                         | compute NDNHeight
    ADD.W       0x18(A4),D0                     | + BTCDepth
    SUB.W       0x10(A4),D0                     | - BTCLevel
    MOVE.B      D0,0x9(A2)                      | set NDNHeight
    CMPI.B      #0xFF,0x8(A2)                   | new leaf node?
    BNE.B       SPLITLT_DOROTATE                | no ->
    TST.L       0x4(A2)                         | first leaf? (NDBLink = 0?)
    BNE.B       SPLITLT_DOROTATE                | no ->
    MOVE.L      D3,0x22(A4)                     | update BTCFNode
SPLITLT_DOROTATE:
    MOVEA.L     D7,A0                           | ptr to new record
    MOVE.W      D6,D0                           | new record size
    MOVE.W      D5,D1                           | insert index
    JSR         ROTATELT(PC)                    | RotateLT: insert via rotation
    BEQ.B       SPLITLT_DONE                    | ok ->
    BRA.B       SPLITLT_EXIT                    | error ->
SPLITLT_DONE:
    CLR.W       D0                              | result = ok
    MOVE.L      D3,D2                           | D2 = new left node number
SPLITLT_EXIT:
    MOVEM.L     (A6)+,D3-D7/A3                  | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from SPLITLT
TREESEARCH:
    MOVE.L      (0x7CC).W,-(A7)                 | HFS vector: TreeSearch trampoline
    RTS                                         | dispatch via vector
| TreeSearch: descend B-tree from root to leaf
VTREESEARCH:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D3-D7/A2-A3,-(A6)               | save regs
    MOVE.L      A0,D7                           | D7 = search key
    TST.W       0x18(A4)                        | tree empty? (BTCDepth)
    BGT.B       TSRCH_START                     | no ->
    MOVEQ.L     #0x20,D0                        | result = BTnotfound
    SUBA.L      A1,A1                           | no node
    MOVEQ.L     #0x0,D1                         | index = 0
    MOVEQ.L     #0x0,D2                         | node = 0
    CLR.W       0x10(A4)                        | BTCLevel = 0
    BRA.B       TSRCH_EXIT                      | exit ->
| TSSearch: start at root, descend to leaf
TSRCH_START:
    MOVEQ.L     #0x1,D6                         | D6 = current level (1=root)
    MOVE.L      0x1A(A4),D3                     | D3 = root node number (BTCRoot)
| TSGetNode: get node and search within it
TSRCH_LOOP:
    MOVEQ.L     #0x0,D1                         | no options
    MOVE.L      D3,D2                           | node number
    JSR         GETNODE(PC)                     | read node into cache
    BNE.B       TSRCH_EXIT                      | error ->
    MOVEA.L     A0,A1                           | A1 = node buffer
    MOVEA.L     D7,A0                           | A0 = search key
    JSR         SEARCHNODE(PC)                  | binary search within node
    MOVE.W      D0,D5                           | D5 = search result (0=found)
    MOVE.W      D1,D4                           | D4 = record index
| TSUpdTPR: save current position in TPR
    MOVE.W      D6,D0                           | current level
    JSR         LOCTPR(PC)                      | locate TPR entry -> A0
    MOVEA.L     A0,A3                           | A3 = TPR entry
    MOVE.L      D3,(A3)                         | TPRNodeN = current node
    MOVE.W      D4,D2                           | D2 = record index
    TST.W       D5                              | key found?
    BEQ.B       TSRCH_SETINDX                   | yes, use index as-is ->
    SUBQ.W      #0x1,D2                         | not found: back up one
    BGE.B       TSRCH_SETINDX                   | ok ->
    MOVE.W      D4,D2                           | clamp to 0
TSRCH_SETINDX:
    MOVE.W      D2,0x4(A3)                      | TPRRIndx = record index
    CMP.W       0x18(A4),D6                     | at leaf level? (BTCDepth)
    BEQ.B       TSRCH_LEAF                      | yes, done ->
| TSDescend: follow child pointer to next level
    MOVE.W      D2,D1                           | record index
    MOVE.L      A1,-(A7)                        | save node buffer
    JSR         LOCREC(PC)                      | locate record -> A1
    MOVE.L      (A1),D3                         | D3 = child node number
    MOVEA.L     (A7)+,A1                        | restore node buffer
    MOVEQ.L     #0x0,D1                         | release without write
    MOVEA.L     A1,A0                           | A0 = node buffer
    JSR         RELNODE(PC)                     | release current node
    ADDQ.W      #0x1,D6                         | advance to next level
    BRA.B       TSRCH_LOOP                      | continue descending ->
| TSDone: at leaf level, return result
TSRCH_LEAF:
    MOVE.W      D6,0x10(A4)                     | BTCLevel = leaf level
    MOVE.W      D4,D1                           | D1 = record index
    MOVE.W      D5,D0                           | D0 = search result
    MOVE.L      D3,D2                           | D2 = leaf node number
TSRCH_EXIT:
    MOVEM.L     (A6)+,D3-D7/A2-A3               | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from TreeSearch
| RotRecLT: move first record from right to end of left node
ROT_RECLT:
    MOVEM.L     A2-A3,-(A7)                     | save regs
    MOVEA.L     A0,A2                           | A2 = left node (dest)
    MOVEA.L     A1,A3                           | A3 = right node (source)
    MOVEQ.L     #0x0,D0                         | record 0 (first record)
    JSR         GETRECA(PC)                     | get first record from right
    LEA.L       0xE(A1),A0                      | A0 = record data (skip ND header)
    MOVEA.L     A2,A1                           | A1 = left node
    MOVE.W      0xA(A1),D1                      | insert at end of left node
    JSR         INSERTREC(PC)                   | insert into left node
    MOVEA.L     A3,A1                           | A1 = right node
    BEQ.B       ROTRECLT_DEL                    | insert ok ->
    MOVEQ.L     #-0x1,D0                        | result = error
    BRA.B       ROTRECLT_EXIT                   | exit ->
ROTRECLT_DEL:
    CLR.W       D1                              | delete record 0 from right
    JSR         DELETEREC(PC)                   | remove first record
    CLR.W       D0                              | result = noErr
ROTRECLT_EXIT:
    TST.W       D0                              | set condition codes
    MOVEM.L     (A7)+,A2-A3                     | restore regs
    RTS                                         | return from RotRecLT
| BuildIRec: build index record (key + child node ptr)
BTMAINT2:                                       | Apple source module (MacSEROM.lst)
BUILDIREC:
    MOVE.L      D2,-(A7)                        | save D2
    MOVE.L      D0,D2                           | D2 = child node number
    CLR.W       D0                              | record 0 (first key)
    BSR.W       GETRECA                         | get first key from child -> A0
    MOVEA.L     0xC(A4),A1                      | A1 = BTCVarPtr
    LEA.L       0x30(A1),A1                     | offset to BTVRecord buffer
    JSR         UPDIKEY(PC)                     | copy key to index record
    BSR.W       GETMAXKEY                       | D0 = max key length
    MOVE.L      D2,0x0(A1,D0.W)                 | store child node ptr after key
    MOVE.L      (A7)+,D2                        | restore D2
    RTS                                         | return from BuildIRec
| ChkNode: validate a B-tree node's structure
CHKNODE:
    MOVEM.L     D1-D2/A0-A2,-(A7)               | save regs
    MOVE.W      0x2(A4),D1                      | file refnum (BTCRefNum)
    MOVEA.L     (FCBSPtr).W,A2                  | FCB array base
    MOVE.L      0xC(A2,D1.W),D0                 | PEOF from FCB
    DIVU.W      0x2A(A4),D0                     | total nodes = PEOF / nodeSize
    MOVEQ.L     #0x0,D1                         | clear high word
    MOVE.W      D0,D1                           | D1 = total node count
    CMP.L       (A1),D1                         | NDFLink within range?
    BLS.B       CHKNODE_BAD                     | no ->
    CMP.L       0x4(A1),D1                      | NDBLink within range?
    BLS.B       CHKNODE_BAD                     | no ->
    MOVE.B      0x8(A1),D0                      | NDType
    ADDQ.B      #0x1,D0                         | valid type 0-2? (+1 to check <=2)
    CMPI.B      #0x3,D0                         | type 0,1,2 only (index/header/map)
    BHI.B       CHKNODE_BAD                     | invalid ->
    MOVE.B      0x9(A1),D0                      | NDNHeight
    CMP.B       0x19(A4),D0                     | <= BTCDepth+1?
    BHI.B       CHKNODE_BAD                     | no ->
    MOVEQ.L     #0x0,D1                         | clear
    MOVE.W      0x2A(A4),D1                     | node size (BTCNodeSize)
    MOVEQ.L     #-0xE,D0                        | max records = (nodeSize-14)/6
    ADD.L       D1,D0                           | (min record = key(4)+data(0)+offset(2))
    DIVU.W      #0x6,D0                         | D0 = max records per node
    CMP.W       0xA(A1),D0                      | NDNRecs within max?
    BCS.B       CHKNODE_BAD                     | no ->
| validate offset table entries
    MOVE.W      0xA(A1),D1                      | D1 = NDNRecs (loop count)
    MOVE.W      D1,D0                           | get offset of last entry
    BSR.W       GETOFFSET                       | -> A0, D0
    MOVEQ.L     #0x2,D2                         | minimum allowed offset
    ADD.L       A0,D2                           | D2 = end of offset table
    SUB.L       A1,D2                           | relative to node start
CHKNODE_OFFLOOP:
    MOVE.W      (A0)+,D0                        | get offset entry
    BTST        #0x0,D0                         | must be even
    BNE.B       CHKNODE_BAD                     | odd offset ->
    CMPI.W      #0xE,D0                         | must be >= 14 (after ND header)
    BCS.B       CHKNODE_BAD                     | too small ->
    CMP.W       D2,D0                           | must be < previous offset
    BCC.B       CHKNODE_BAD                     | not decreasing ->
    MOVE.W      D0,D2                           | update limit
    DBF.W       D1,CHKNODE_OFFLOOP              | loop for all entries
    BRA.B       CHKNODE_OK                      | all valid ->
| Called by: CHKNODE, CHKNODE_OFFLOOP
CHKNODE_BAD:
    MOVEQ.L     #0x24,D0                        | result = BTbadNode
    BRA.B       CHKNODE_EXIT                    | exit ->
CHKNODE_OK:
    CLR.W       D0                              | result = noErr
CHKNODE_EXIT:
    MOVEM.L     (A7)+,D1-D2/A0-A2               | restore regs
    TST.W       D0                              | set condition codes
    RTS                                         | return from ChkNode
| ClrNode: zero out a node buffer
CLRNODE:
    MOVEM.L     D0-D1/A0,-(A7)                  | save regs
    MOVEQ.L     #0x3,D1                         | round node size to longwords
    ADD.W       0x2A(A4),D1                     | + node size (BTCNodeSize)
    LSR.W       #0x2,D1                         | / 4 = longword count
    SUBQ.W      #0x1,D1                         | adjust for DBF
    MOVEQ.L     #0x0,D0                         | zero fill value
CLRNODE_LOOP:
    MOVE.L      D0,(A0)+                        | clear longword
    DBF.W       D1,CLRNODE_LOOP                 | loop for entire node
    MOVEM.L     (A7)+,D0-D1/A0                  | restore regs
    RTS                                         | return from ClrNode
| DeleteRec: remove record at index D1 from node A1
DELETEREC:
    MOVEM.L     D2-D6/A2-A5,-(A7)               | save regs
    MOVE.W      D1,D5                           | D5 = record index to delete
    MOVE.W      D1,D0                           | get offset of record to delete
    JSR         GETOFFSET(PC)                   | -> A0=offset table ptr, D0=offset
    MOVE.L      A0,D6                           | save offset table ptr
    MOVE.W      D0,D4                           | D4 = start offset of record
    LEA.L       -0x2(A0),A3                     | A3 = ptr to previous offset entry
    MOVE.W      (A3),D3                         | D3 = end offset of record
    MOVE.W      0xA(A1),D0                      | get offset of free space
    JSR         GETOFFSET(PC)                   | -> A0=ptr, D0=offset
    MOVEA.L     A0,A2                           | save end of offset table
    MOVE.W      D0,D2                           | D2 = free space offset
| close gap in record data area
    MOVEA.L     A1,A5                           | A5 = node base
    LEA.L       0x0(A5,D3.W),A0                 | source = after deleted record
    LEA.L       0x0(A5,D4.W),A1                 | dest = start of deleted record
    MOVE.W      D2,D0                           | byte count = free - end
    SUB.W       D3,D0                           | of deleted record
    JSR         MOVRECLT(PC)                    | shift records left
    SUBQ.W      #0x1,0xA(A5)                    | decrement NDNRecs
| adjust offset table entries
    MOVEA.L     A3,A0                           | source = deleted offset entry
    MOVEA.L     D6,A1                           | dest = next entry
    MOVE.W      0xA(A5),D0                      | count = remaining entries
    SUB.W       D5,D0                           | after deleted index
    MOVE.W      D4,D1                           | record size = end - start
    SUB.W       D3,D1                           | (negative = shift amount)
    JSR         MOVOFFRT(PC)                    | shift offsets right
    MOVEM.L     (A7)+,D2-D6/A2-A5               | restore regs
    RTS                                         | return from DeleteRec
| GetLTSib: get left sibling node
GETLTSIB:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D2-D3,-(A6)                     | save regs
    CLR.B       D3                              | D3 = 0: get backward link
    BRA.B       GETSIB_COMMON                   | ->
| GetRTSib: get right sibling node
GETRTSIB:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D2-D3,-(A6)                     | save regs
    MOVEQ.L     #0x1,D3                         | D3 = 1: get forward link
GETSIB_COMMON:
    TST.B       D3                              | forward or backward?
    BNE.B       GETSIB_RIGHT                    | forward ->
    MOVE.L      0x4(A0),D2                      | D2 = NDBLink (backward)
    BRA.B       GETSIB_TEST                     | ->
GETSIB_RIGHT:
    MOVE.L      (A0),D2                         | D2 = NDFLink (forward)
GETSIB_TEST:
    BNE.B       GETSIB_DOREAD                   | has sibling ->
    MOVEQ.L     #0x0,D1                         | D1 = 0 (no sibling)
    BRA.B       GETSIB_NOERR                    | ->
GETSIB_DOREAD:
    MOVEQ.L     #0x0,D1                         | no options
    BSR.B       GETNODE                         | read sibling into cache
    BNE.B       GETSIB_EXIT                     | error ->
    MOVE.L      D2,D1                           | D1 = sibling node number
    MOVEA.L     A0,A1                           | A1 = sibling node buffer
GETSIB_NOERR:
    CLR.W       D0                              | result = noErr
GETSIB_EXIT:
    MOVEM.L     (A6)+,D2-D3                     | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from GetLTSib/GetRTSib
| GetMaxKey: return max key length rounded to even
| Called by: BTINS_NEWROOT, BTINS_RELLEFT, GETBTVARSIZE, BUILDIREC
GETMAXKEY:
    MOVEQ.L     #0x1,D0                         | round up to even
    ADD.W       0x2C(A4),D0                     | + BTCKeyLen (max key length)
    LSR.W       #0x1,D0                         | / 2
    LSL.W       #0x1,D0                         | * 2 (round to even)
    RTS                                         | return max key len in D0
| GetNode: read a B-tree node from cache with validation
| Called by: BTDEL_GETPAR, BTDEL_UPDDEPTH, VBTFLUSH, GR_GETNODE, BTINS_NXTLEV (and 5 more)
GETNODE:
    MOVE.L      (0x750).W,-(A7)                 | HFS vector: GetNode trampoline
    RTS                                         | dispatch via vector
VGETNODE:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1/A1,-(A6)                     | save regs
    MOVE.W      0x2(A4),D0                      | file refnum (BTCRefNum)
    MOVEA.L     0x8(A4),A1                      | cache queue (BTCCQPtr)
    JSR         GETBLOCK(PC)                    | read block into cache -> A0
    BNE.B       GETNODE_EXIT                    | error ->
    MOVEA.L     A0,A1                           | validate node structure
    BSR.W       CHKNODE                         | check node integrity
    BEQ.B       GETNODE_EXIT                    | valid ->
| invalid node: release block and return error
    MOVE.W      D0,-(A6)                        | save ChkNode error
    MOVEQ.L     #0x2,D1                         | release clean
    MOVEA.L     0x8(A4),A1                      | cache queue
    JSR         RELBLOCK(PC)                    | release bad block
    MOVE.W      (A6)+,D0                        | restore error code
GETNODE_EXIT:
    MOVEM.L     (A6)+,D1/A1                     | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from GetNode
| GetNodeSiz: return total data size of node (records + offsets)
GETNODESIZ:
    MOVE.L      D1,-(A7)                        | save D1
    MOVE.W      0xA(A1),D1                      | D1 = NDNRecs
    MOVE.W      D1,D0                           | get free-space offset
    JSR         GETOFFSET(PC)                   | D0 = offset of free space
    SUBI.W      #0xE,D0                         | subtract ND header (14 bytes)
    LSL.W       #0x1,D1                         | D1 = NDNRecs * 2 (offset table)
    ADD.W       D1,D0                           | D0 = data + offset table size
    MOVE.L      (A7)+,D1                        | restore D1
    RTS                                         | return node data size in D0
| GetOffset: get offset value for record index D0 in node A1
| Called by: DELETEREC, GETRECA, INSERTREC, CHKNODE, GETNODESIZ
GETOFFSET:
    BSR.B       GET_OFFA                        | get offset table address -> A0
    MOVE.W      (A0),D0                         | D0 = offset value
    RTS                                         | return offset in D0
| ----------------------------------------------------------
|
| GET_OFFA - GetOffA: get offset address
|
| GetOffA: compute offset table address for record index D0
GET_OFFA:
    SUBA.L      A0,A0                           | clear A0
    MOVEA.W     0x2A(A4),A0                     | A0 = node size (BTCNodeSize)
    ADDA.L      A1,A0                           | A0 = end of node
    LSL.W       #0x1,D0                         | D0 * 2 (word offset)
    NEG.W       D0                              | negate (offsets grow backward)
    LEA.L       -0x2(A0,D0.W),A0                | A0 = offset table entry address
    RTS                                         | return entry address in A0
| GetRecA: get record address and size for index D0 in node A1
| Returns: A0=record ptr, D0=record size
| Called by: BTDEL_GETPAR, BTINS_NXTLEV, GETMAP_LOCREC, LOCREC, ROTLT_SKIPADJ (and 3 more)
GETRECA:
    MOVEM.L     D1-D2,-(A7)                     | save regs
    MOVE.W      D0,D1                           | save record index
    BSR.B       GETOFFSET                       | D0 = offset[index]
    MOVE.W      D0,D2                           | D2 = start offset
    MOVE.W      D1,D0                           | get next offset
    ADDQ.W      #0x1,D0                         | index + 1
    BSR.B       GETOFFSET                       | D0 = offset[index+1]
    SUB.W       D2,D0                           | D0 = record size
    LEA.L       0x0(A1,D2.W),A0                 | A0 = record address
    MOVEM.L     (A7)+,D1-D2                     | restore regs
    RTS                                         | return from GetRecA
| InitNode: allocate and initialize an empty node
INITNODE:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVEM.L     D1-D2/A1,-(A6)                  | save regs
    MOVE.L      D1,D2                           | save node number
    MOVE.W      0x2(A4),D0                      | file refnum (BTCRefNum)
    MOVEQ.L     #0x4,D1                         | D1 = GBnew (allocate new block)
    MOVEA.L     0x8(A4),A1                      | cache queue (BTCCQPtr)
    JSR         GETBLOCK(PC)                    | get empty cache block -> A0
    BNE.B       INITNODE_EXIT                   | error ->
    BSR.W       CLRNODE                         | zero the node
    MOVE.W      0x2A(A4),D2                     | D2 = node size (BTCNodeSize)
    MOVE.W      #0xE,-0x2(A0,D2.W)              | initial free-space offset = 14
    CLR.W       D0                              | result = noErr
INITNODE_EXIT:
    MOVEM.L     (A6)+,D1-D2/A1                  | restore regs
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from InitNode
| InsertRec: insert record at index D1 in node A1
| Input: A0=record data, D0=record size, A1=node, D1=insert index
| Called by: BTINS_NEWROOT, BTINS_INSERT, ROTLT_LOOP, ROTLT_CHKRT2, ROT_RECLT
INSERTREC:
    MOVEM.L     D1-D7/A1-A5,-(A7)               | save regs
    MOVE.W      D0,D7                           | D7 = record size
    MOVE.W      D1,D6                           | D6 = insert index
    MOVE.L      A0,D5                           | D5 = ptr to record data
    MOVE.W      D1,D0                           | get insertion point offset
    JSR         GETOFFSET(PC)                   | D0 = offset[index]
    MOVE.W      D0,D4                           | D4 = insertion offset
    MOVE.W      0xA(A1),D0                      | get free-space offset
    JSR         GETOFFSET(PC)                   | -> A0=end of offset table
    MOVEA.L     A0,A3                           | A3 = end of offset table
    MOVE.W      D0,D3                           | D3 = free-space offset
| check if record fits
    MOVE.L      A3,D1                           | end of offset table
    MOVEQ.L     #0x0,D0                         | clear
    MOVE.W      D3,D0                           | free space start
    ADD.L       A1,D0                           | absolute address
    SUB.L       D0,D1                           | D1 = available space
    MOVEQ.L     #0x2,D0                         | need record + offset entry
    ADD.W       D7,D0                           | total needed
    CMP.W       D0,D1                           | fits?
    BGE.B       INSREC_FIT                      | yes ->
    MOVEQ.L     #-0x1,D0                        | result = doesn't fit
    BRA.B       INSREC_EXIT                     | exit ->
| ----------------------------------------------------------
|
| INSREC_FIT
|
| IRInsert: make hole and copy record data
INSREC_FIT:
    MOVEA.L     A1,A5                           | A5 = node base
    LEA.L       0x0(A5,D4.W),A0                 | source = insertion point
    LEA.L       0x0(A0,D7.W),A1                 | dest = shifted position
    MOVE.W      D3,D0                           | bytes to shift = free - insert
    SUB.W       D4,D0                           | count
    JSR         MOVRECRT(PC)                    | shift existing records right
| shift offset table entries left (make room for new entry)
    MOVEA.L     A3,A0                           | source = end of offset table
    LEA.L       -0x2(A0),A1                     | dest = one entry earlier
    MOVE.W      0xA(A5),D0                      | count = entries after insert
    SUB.W       D6,D0                           | point
    MOVE.W      D7,D1                           | adjustment = record size
    JSR         MOVOFFLT(PC)                    | shift offsets and adjust values
| copy record data into the hole
    MOVEA.L     D5,A0                           | source = record data
    LEA.L       0x0(A5,D4.W),A1                 | dest = insertion point
    MOVE.W      D7,D0                           | byte count = record size
    JSR         MOVRECLT(PC)                    | copy record data
    ADDQ.W      #0x1,0xA(A5)                    | increment NDNRecs
    CLR.W       D0                              | result = noErr
INSREC_EXIT:
    MOVEM.L     (A7)+,D1-D7/A1-A5               | restore regs
    TST.W       D0                              | set condition codes
    RTS                                         | return from InsertRec
| LocBTCB: locate BTCB from FCB extension pointer
| Called by: VBTCLOSE, VBTFLUSH, VBTINSERT, VBTUPDATE, BT_SETUP
LOCBTCB:
    MOVEA.L     (FCBSPtr).W,A4                  | A4 = FCB array base
    MOVEA.L     0x22(A4,D0.W),A4                | A4 = BTCB ptr (FCBBTCBPtr)
    RTS                                         | return from LocBTCB
| LocRec: locate record, returning key ptr (A0) and data ptr (A1)
| Called by: BTDEL_UPDDEPTH, BTREC_FOUND, BTSRCH_FOUND, TSRCH_SETINDX, UPDDREC
LOCREC:
    MOVEM.L     D0/D2-D3,-(A7)                  | save regs
    MOVE.W      D1,D3                           | D3 = record index
    MOVE.W      D3,D0                           | get record address
    JSR         GETRECA(PC)                     | A0 = record, D0 = size
    MOVE.L      A0,D2                           | save record address
    MOVE.W      D3,D0                           | get key length
    ADDQ.W      #0x1,D0                         | next record (for end offset)
    JSR         GETRECA(PC)                     | A0 = next record start
    MOVE.L      A0,D1                           | D1 = end of current record
    MOVEA.L     D2,A0                           | A0 = key (record start)
    MOVEQ.L     #0x0,D0                         | clear for key length
    MOVE.B      (A0),D0                         | D0 = key length byte
    ADDQ.L      #0x2,D0                         | + length byte, round up
    LSR.L       #0x1,D0                         | round to even
    LSL.L       #0x1,D0                         | (key size with padding)
    SUB.L       D2,D1                           | D1 = total record size
    SUB.L       D0,D1                           | D1 = data record size
    MOVEA.L     A0,A1                           | A1 = data ptr (key + key size)
    ADDA.L      D0,A1                           | skip past key to data
    MOVEM.L     (A7)+,D0/D2-D3                  | restore regs
    RTS                                         | return from LocRec
| LocTPR: locate Tree Path Record for level D0
| Returns: A0 = TPR entry (6 bytes: nodeN + rIndx + reserved)
| Called by: BDFREE, BTDEL_GETPAR, BTINS_NXTLEV, BTINS_NEWROOT, SPLITLT (and 1 more)
LOCTPR:
    SUBQ.W      #0x1,D0                         | level 1-based -> 0-based
    MULU.W      #0x6,D0                         | * 6 bytes per TPR entry
    MOVEA.L     0xC(A4),A0                      | A0 = BTCVarPtr base
    LEA.L       0x0(A0,D0.L),A0                 | A0 = TPR entry for level
    RTS                                         | return TPR address in A0
| MovOffLT: shift D0+1 offset entries left, adding D1 to each
MOVOFFLT:
    MOVEM.L     D0-D2/A0-A1,-(A7)               | save regs
MOVOFFLT_LOOP:
    MOVE.W      (A0)+,D2                        | read offset entry
    ADD.W       D1,D2                           | adjust by shift amount
    MOVE.W      D2,(A1)+                        | write shifted entry
    DBF.W       D0,MOVOFFLT_LOOP                | loop for all entries
    BRA.B       MOVOFF_RETURN                   | ->
| MovOffRT: shift D0+1 offset entries right, adding D1 to each
MOVOFFRT:
    MOVEM.L     D0-D2/A0-A1,-(A7)               | save regs
    CMPM.W      (A0)+,(A1)+                     | advance pointers past end
MOVOFFRT_LOOP:
    MOVE.W      -(A0),D2                        | read offset entry (backward)
    ADD.W       D1,D2                           | adjust by shift amount
    MOVE.W      D2,-(A1)                        | write shifted entry
    DBF.W       D0,MOVOFFRT_LOOP                | loop for all entries
MOVOFF_RETURN:
    MOVEM.L     (A7)+,D0-D2/A0-A1               | restore regs
    RTS                                         | return from MovOff
| MovRecLT: copy D0 bytes forward (A0)+ -> (A1)+
MOVRECLT:
    MOVEM.L     D0-D1/A0-A1,-(A7)               | save regs
    TST.W       D0                              | anything to copy?
    BLE.B       MOVRECLT_EXIT                   | no ->
    SUBQ.W      #0x1,D0                         | adjust for DBF
MOVRECLT_LOOP:
    MOVE.B      (A0)+,(A1)+                     | copy byte forward
    DBF.W       D0,MOVRECLT_LOOP                | loop for all bytes
MOVRECLT_EXIT:
    MOVEM.L     (A7)+,D0-D1/A0-A1               | restore regs
    RTS                                         | return from MovRecLT
| MovRecRT: copy D0 bytes backward -(A0) -> -(A1)
MOVRECRT:
    MOVEM.L     D0-D1/A0-A1,-(A7)               | save regs
    TST.W       D0                              | anything to copy?
    BLE.B       MOVRECRT_EXIT                   | no ->
    ADDA.W      D0,A0                           | start from end of source
    ADDA.W      D0,A1                           | start from end of dest
    SUBQ.W      #0x1,D0                         | adjust for DBF
MOVRECRT_LOOP:
    MOVE.B      -(A0),-(A1)                     | copy byte backward
    DBF.W       D0,MOVRECRT_LOOP                | loop for all bytes
MOVRECRT_EXIT:
    MOVEM.L     (A7)+,D0-D1/A0-A1               | restore regs
    RTS                                         | return from MovRecRT
| RelNode: release a B-tree node via block cache
| Called by: BTINS_CLEANUP, BTDEL_CHKRECS, BTDEL_GETRSIB, BDFREE, BTDEL_RELCHILD (and 12 more)
RELNODE:
    MOVE.L      (0x754).W,-(A7)                 | HFS vector: RelNode trampoline
    RTS                                         | dispatch via vector
VRELNODE:
    MOVE.L      (A7)+,-(A6)                     | save return address on A6 stack
    MOVE.L      A1,-(A6)                        | save A1
    MOVE.L      A0,D0                           | node buffer null?
    BEQ.B       RELNODE_SKIP                    | yes, nothing to release ->
    JSR         RELBLOCK(PC)                    | release block via cache
RELNODE_SKIP:
    MOVEA.L     (A6)+,A1                        | restore A1
    MOVE.L      (A6)+,-(A7)                     | restore return address to stack
    TST.W       D0                              | set condition codes
    RTS                                         | return from RelNode
| SearchNode: binary search within a B-tree node
| Input: A0=search key, A1=node buffer
| Returns: D0=0 if found, D0=BTnotfound if not; D1=record index
SEARCHNODE:
    MOVEM.L     D2-D5/A1-A3,-(A7)               | save regs
    MOVEA.L     A0,A3                           | A3 = search key
    MOVEA.L     A1,A2                           | A2 = node buffer
    MOVE.L      0x4(A4),D5                      | D5 = key compare proc (BTCKeyCR)
    CLR.W       D2                              | D2 = low bound (0)
    MOVE.W      0xA(A2),D3                      | D3 = high bound (NDNRecs)
    SUBQ.W      #0x1,D3                         | adjust to last index
    CMP.W       D3,D2                           | any records?
    BGT.B       SRCHNODE_NOTFND                 | no ->
| SrchLoop: binary search
SRCHNODE_LOOP:
    MOVE.W      D2,D4                           | mid = (low + high) / 2
    ADD.W       D3,D4                           | (low + high)
    LSR.W       #0x1,D4                         | / 2
    MOVE.W      D4,D0                           | get record at mid
    MOVEA.L     A2,A1                           | node buffer
    JSR         GETRECA(PC)                     | A0 = trial record
    MOVEA.L     A0,A1                           | A1 = trial key
    MOVEA.L     A3,A0                           | A0 = search key
    MOVE.L      A4,-(A7)                        | save BTCB ptr
    MOVEA.L     D5,A4                           | call key compare via ptr
    JSR         (A4)                            | compare(search, trial)
    MOVEA.L     (A7)+,A4                        | restore BTCB ptr
    TST.W       D0                              | compare result
    BEQ.B       SRCHNODE_EQ                     | equal: found ->
    BGT.B       SRCHNODE_GT                     | search > trial ->
| SrchLT: search < trial, narrow high bound
    MOVE.W      D4,D3                           | high = mid
    SUBQ.W      #0x1,D3                         | - 1
    CMP.W       D3,D2                           | low <= high?
    BLE.B       SRCHNODE_LOOP                   | yes, continue ->
    BRA.B       SRCHNODE_NOTFND                 | not found ->
| SrchEQ: found exact match
SRCHNODE_EQ:
    CLR.W       D0                              | result = found (0)
    BRA.B       SRCHNODE_EXIT                   | ->
| ----------------------------------------------------------
|
| SRCHNODE_GT
|
| SrchGT: search > trial, narrow low bound
SRCHNODE_GT:
    MOVE.W      D4,D2                           | low = mid
    ADDQ.W      #0x1,D2                         | + 1
    CMP.W       D3,D2                           | low <= high?
    BLE.B       SRCHNODE_LOOP                   | yes, continue ->
| SrchNotFnd: key not found, D2 = insertion point
SRCHNODE_NOTFND:
    MOVE.W      D2,D4                           | D4 = insertion index
    MOVEQ.L     #0x20,D0                        | result = BTnotfound
SRCHNODE_EXIT:
    MOVE.W      D4,D1                           | D1 = record index
    MOVEM.L     (A7)+,D2-D5/A1-A3               | restore regs
    TST.W       D0                              | set condition codes
    RTS                                         | return from SearchNode
| UpdDRec: replace junk data record with real data after BTInsert
| Input: A0=source data (or nil to clear), D0=data size
UPDDREC:
    MOVEM.L     D0-D1/A0-A2,-(A7)               | save regs
    MOVEA.L     A0,A2                           | A2 = source data ptr
    JSR         LOCREC(PC)                      | locate record -> A0=key, A1=data
    MOVE.L      A2,D1                           | source provided?
    BEQ.B       UPDDREC_CLR                     | no, clear data area ->
    MOVEA.L     D1,A0                           | A0 = source data
    EXT.L       D0                              | sign-extend for BlockMove
    _BlockMove                                  | copy real data into record
    BRA.B       UPDDREC_EXIT                    | ->
UPDDREC_CLRLOOP:
    CLR.B       (A1)+                           | zero fill data area
UPDDREC_CLR:
    DBF.W       D0,UPDDREC_CLRLOOP              | loop for all bytes
UPDDREC_EXIT:
    MOVEM.L     (A7)+,D0-D1/A0-A2               | restore regs
    RTS                                         | return from UpdDRec
| UpdIKey: update index key to max key length with padding
| Input: A0=source key, A1=dest key buffer
UPDIKEY:
    MOVEM.L     D0-D1/A0-A2,-(A7)               | save regs
    MOVEA.L     A0,A2                           | save source ptr
    MOVE.W      0x2C(A4),D1                     | D1 = max key length (BTCKeyLen)
    MOVE.B      D1,(A1)+                        | write max key length byte
    MOVEA.L     A2,A0                           | A0 = source key
    MOVE.B      (A0)+,D0                        | D0 = actual key length
    EXT.W       D0                              | sign-extend for arithmetic
    SUB.W       D0,D1                           | D1 = padding needed
    BGE.B       UPDIKEY_CPYTEST                 | key fits ->
    ADD.W       D1,D0                           | clamp to max length
    BRA.B       UPDIKEY_CPYTEST                 | ->
UPDIKEY_CPYLOOP:
    MOVE.B      (A0)+,(A1)+                     | copy key byte
UPDIKEY_CPYTEST:
    DBF.W       D0,UPDIKEY_CPYLOOP              | loop for key length
    TST.W       D1                              | any padding needed?
    BLE.B       UPDIKEY_EXIT                    | no ->
    BRA.B       UPDIKEY_PADTEST                 | ->
UPDIKEY_PADLOOP:
    CLR.B       (A1)+                           | zero pad byte
UPDIKEY_PADTEST:
    DBF.W       D1,UPDIKEY_PADLOOP              | loop for remaining bytes
UPDIKEY_EXIT:
    MOVEM.L     (A7)+,D0-D1/A0-A2               | restore regs
    RTS                                         | return from UpdIKey
