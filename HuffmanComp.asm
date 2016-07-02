
      .486                                      
      .model flat, stdcall                      
      option casemap :none                     
      DEBUG EQU 1
      include    windows.inc
      include    kernel32.inc
      include    masmlib.inc
      includelib user32.lib
      include    user32.inc
          
      GET_TREE   EQU   1
      GET_CODE   EQU   0
      SIGN_ALLOC_FAIL  EQU  1
	  SIGN_RANGE_OUT   EQU  2
	  SIGN_INVALID     EQU  3
 
      HNODE STRUCT
          weight   DWORD 0
          isLeaf   DWORD 0 
          bValue   DWORD 0 
          lpParent DWORD 0 
          lpLeft   DWORD 0
          lpRight  DWORD 0
      HNODE ENDS 
      
      HUFFCODE STRUCT
          bValue DWORD 0
          bDepth DWORD 0
          bitVal DWORD 0
      HUFFCODE ENDS

      CreatHuffManTabl  PROTO STDCALL :DWORD,:DWORD,:DWORD
      FindBiggest PROTO :DWORD
      FindSmallest  PROTO STDCALL :DWORD,:DWORD
      HuffManBuild PROTO STDCALL :DWORD,:DWORD
      Compress PROTO STDCALL :DWORD,:DWORD,:DWORD
      UnCompress PROTO STDCALL :DWORD,:DWORD

    .DATA?  
      fName    BYTE  200 DUP (?)  
      fOutName BYTE  200 DUP (?)     
      hFileIn  DWORD ?                 
      hFileOut DWORD ?              
      hMemF    DWORD ?                
      hMemB    DWORD ?                 
      fSize    DWORD ?                 
      rwSize   DWORD ?   
          
    .CODE
    
Starts:
     INVOKE GetCL,1,OFFSET fName
     .IF EAX == 1
        INVOKE GetCL,2,OFFSET fOutName
        .IF EAX == 1
             JMP @F
       .ENDIF
     .ENDIF
    exit        
   @@:
    .IF fopen(OFFSET fName,OPEN_EXIST)!=INVALID_HANDLE_VALUE
       MOV hFileIn,eax    
      .IF fopen(OFFSET fOutName,OPEN_NEW)!=INVALID_HANDLE_VALUE
         MOV hFileOut,eax 
         JMP @F
      .ENDIF
    .ENDIF
    exit 
   @@:
    MOV fSize, rv(FileSize,OFFSET fName)
    MOV EAX, fSize
    LEA EAX, [EAX*8]
	LEA EAX, [EAX*2]
    .IF alloc(EAX)!=NULL
      MOV hMemB,EAX
      MOV EAX, fSize
      ADD EAX, 1200h
      .IF alloc(EAX)!=NULL
        MOV hMemF,EAX 
        JMP @F            
      .ENDIF
    .ENDIF 
	PUSH SIGN_ALLOC_FAIL
	CALL FatalError  
   @@:
    .IF fread(hFileIn,hMemF,fSize)!=fSize   
       JMP @ERM5
    .ENDIF

      INVOKE Compress,hMemF,hMemB,fSize
      MOV rwSize, EAX

    @@:
    .IF fwrite(hFileOut,hMemB,rwSize)!=rwSize
      @ERM5:
       exit         
    .ENDIF      
    fclose(hFileIn)
    fclose(hFileOut)
    exit
	
Compress PROC lpData:DWORD,lpBuf:DWORD,dSize:DWORD
       LOCAL hHuffCode:DWORD 
       LOCAL hHuffTabl:DWORD 
       LOCAL hFreqTabl:DWORD 
       LOCAL BWrite:DWORD 
       LOCAL bitVal:DWORD
       LOCAL bDepth:DWORD
       LOCAL Elems:DWORD
      PUSHAD
      .IF alloc(260*DWORD)==NULL
         PUSH SIGN_ALLOC_FAIL
		 CALL FatalError
      .ENDIF
      MOV hFreqTabl, EAX
      INVOKE CreatHuffManTabl,lpData,hFreqTabl,dSize
      MOV hHuffTabl, EAX               
      INVOKE HuffManBuild,EAX,GET_CODE        
      MOV hHuffCode, EAX               ; 保存指向HUFFCODE结构的指针返回值
      MOV Elems, EBX                   
      MOV ESI, lpData
      MOV EDI, lpBuf     
      MOV EBX, hHuffTabl    
      MOV EAX, dSize
	  MOV WORD PTR[EDI],'DE'           ; 文件头 'ED' 标志 @_@
      MOV DWORD PTR[EDI+2], EAX        ; 写入四字节原始数据大小到缓冲区                                                               
      ADD EDI, 6      
      MOVZX EAX, WORD PTR[EBX]
      MOV WORD PTR[EDI], AX            ; 写入两字节HUFFMAN表元素个数到缓冲区  
      ADD EBX, 2           
      ADD EDI, 2             
      MOV CX, 5                  
      MUL CX                         
      PUSH EAX
      PUSH EDI
      PUSH EBX
      CALL MemMove                     ; 写入HUFFMAN表到缓冲区[长度*5 Bytes] 
      ADD EDI, EAX                     ; 现在指针指向缓冲区中的数据区
      XOR ECX, ECX
      XOR EAX, EAX 
      .WHILE dSize
        PUSHAD
        MOVZX EAX, BYTE PTR[ESI] 
        MOV EBX, hHuffCode
        MOV ECX, Elems
        .WHILE ECX
           CMP EAX, (HUFFCODE PTR[EBX]).bValue
           JE _FOUND
           ADD EBX, SIZEOF HUFFCODE
           DEC ECX
        .ENDW
        PUSH SIGN_RANGE_OUT
		CALL FatalError
       _FOUND:
        MOV EAX, (HUFFCODE PTR[EBX]).bDepth
        MOV bDepth, EAX
        MOV EAX, (HUFFCODE PTR[EBX]).bitVal
        MOV bitVal, EAX
        POPAD
       _WRITEBIT: 
        .IF !ECX                   
           MOV ECX, 32              
        .ENDIF  
        .IF ECX > bDepth            ; 如果该编码长度小于EAX剩余可存入位
           SUB ECX, bDepth          ; 设置移位数 
           SHL bitVal, CL           ; 
           XOR EAX, bitVal          ; 将该编码存入EAX
        .ELSE                      
           SUB bDepth, ECX           ; 否则，切割位，只写入EAX还可存的位，剩余位留待下次    **|| 比如 有四个个编码 01 101 11 1100 ，一个8位的存储器只可以存入8位编码（我们这是假设,EAX是32位的）
           MOV ECX, bDepth           ; 设置移位数，右移位，保留最高可写位，不可写的位暂存EBX  || 存储器已存入前三个编码0110 111x，还有一位没用，但是第四个编码是4位，所以只能存一位，
           PUSH ECX                  ;                                                        || 所以，将最高的位1存入存储器，这样就剩下三个位100，然后把存储器中已经盛满的编码写入缓冲区，
           @@:                       ;                                                        || 直接跳到下一次（不读取下一个字节的编码，因为不是上一个编码还有三位没处理么）
           JECXZ _Out
           SHR bitVal, 1             ; 只保留可存入EAX的最高位
           RCR EBX, 1                ; 将不可存的暂存入 EBX
           DEC ECX                    
           JMP @B
          _Out:
           POP ECX  
	       XOR EAX, bitVal          
           MOV [EDI], EAX            ; 达到此步 EAX 的32个位已存满， 写入缓冲区
           ADD EDI, 4 
           XOR EAX, EAX              ; EAX 清零，准备下次             
           .IF ECX                   
             ROL EBX, CL             ; 将剩余位左移至低位
             MOV bitVal, 0           
             XOR bitVal, EBX         ; 将剩余位存入  bitVal 
             XOR ECX, ECX            
             JMP _WRITEBIT           ; 再次处理
           .ENDIF
         .ENDIF
         INC ESI
         DEC dSize
      .ENDW
      .IF ECX                        ; 如果循环结束还有值在 EAX 中
	 MOV [EDI], EAX                  ; 写入
	 ADD EDI, 4
      .ENDIF
      free(hHuffCode)
      free(hHuffTabl)
      free(hFreqTabl)
      SUB EDI, lpBuf
      MOV BWrite, EDI                ; 最后一次写入的指针-缓冲区基指针 = 写入的字节数
      POPAD
      MOV EAX, BWrite                ; 返回写入缓冲区的字节数
      RET  
Compress ENDP

UnCompress PROC lpCData:DWORD,lpBuf:DWORD
       LOCAL lpTreeRoot:DWORD
       LOCAL hTreeNodes:DWORD
       LOCAL RawSize:DWORD
       LOCAL BWrite:DWORD
       LOCAL hNodes:DWORD
      PUSHAD
      MOV ESI, lpCData                        
      MOV EDI, lpBuf                           
	  .IF WORD PTR[ESI]!='DE'                  ; 测试文件头1-2标志字节，如果不是'ED'那么这不是Compress出来的文件
	     PUSH SIGN_INVALID
		 CALL FatalError
	  .ENDIF
      MOV EAX, [ESI+2]                         ; 读取已压缩数据的第3-6字节(这四字节是原始未压缩数据的大小)
      MOV RawSize, EAX                         ; 存储进变量 RawSize
	  ADD ESI, 6                               ; 标志字节（2）+原始文件大小（4） =6
      INVOKE HuffManBuild,ESI,GET_TREE         ; 从函数中获取一个夫曼树，ESI指向第五个字节
      MOV lpTreeRoot, EAX
      MOV hNodes, EBX
      MOV hTreeNodes, ECX                      ; 存储一下
      MOVZX EAX, WORD PTR[ESI]                 ; 读取第5，6字节（这两字节是紧随其后的HaffTabl中元素数量）
      ADD ESI, 2                                
      MOV CX, 5
      MUL CX                                   ; 将元素数量*5，既是要读取的HuffTable大小
      ADD ESI, EAX                             ; 加上HuffTable大小，那么现在ESI指向编码数据段
      MOV EBX, lpTreeRoot                      ; 初始化一下EBX

     _NEXT:
      MOV EAX, [ESI]                           ; 读取4个字节的编码
      MOV ECX, 32                              ; 设置移位数，EAX 是32位的
     _AGAIN:
      .WHILE ECX                                
        SHL EAX, 1                             ; 左移一位
        JNC _LEFT
           MOV EBX, (HNODE PTR[EBX]).lpRight   ; 有进位，转向父节点右支
           JMP _IFOUT
         _LEFT:
           MOV EBX, (HNODE PTR[EBX]).lpLeft    ; 无进位，转向父节点左支
        _IFOUT:  
        DEC ECX
        CMP (HNODE PTR[EBX]).isLeaf, TRUE      ; 这是一个存储数据的HNODE 吗？
        JE _FOUND                              ; 似的，转到_FOUND
      .ENDW
      JMP @F                                   ; 否则，读取下一个4字节哈夫曼编码
      _FOUND:
       MOV EDX, (HNODE PTR[EBX]).bValue        ; 获取节点中存储的值
       MOV [EDI], DL                           ; 写入缓冲区
       INC EDI
       MOV EBX, lpTreeRoot                     ; 重设 EBX 指向根节点
       DEC RawSize                             
       .IF !RawSize                            ; 如果写入字节数和原始大小相同，那么完成！
          JMP _OK               
       .ENDIF
       .IF ECX                                 ; 如果ECX不为0，说明前一个EAX中还有未读取的哈夫曼位
         JMP _AGAIN                            ; 再来一次，此次不可重设EBX
       .ENDIF
     @@:
       ADD ESI, 4                              ; 指向下一个4字节哈夫曼编码
       JMP _NEXT
     _OK:
      XCHG EDI, lpBuf                          ; 这步是用来返回已写入字节数的，
      SUB lpBuf, EDI                           ; lpBuf指向初始地址，EDI是最后写入的地址，所以交换并相减即为已写入字节数。
      free(hNodes)
      free(hTreeNodes) 
      POPAD                                   
      MOV EAX, lpBuf                           ; 写入返回值
      RET
UnCompress ENDP      

CreatHuffManTabl  PROC lpData:DWORD,lpFreqTabl:DWORD,bCnt:DWORD
       LOCAL nullCnt:DWORD
       LOCAL hHuffTabl:DWORD
          PUSHAD
          MOV ESI, lpData
          MOV EDI, lpFreqTabl
          MOV ECX, bCnt
          ALIGN DWORD
 ; 以下代码收集字节出现频率
        @@:
          MOVZX EAX, BYTE PTR[ESI]
          INC DWORD PTR[EDI+EAX*4]
          INC ESI
          DEC ECX
          JECXZ @F 
          JMP @B
 ; 以下代码构建 HUFFMAN 表， 未出现的字节将被忽略
        @@:  
          .IF alloc(1800)==NULL
             PUSH SIGN_ALLOC_FAIL
             CALL FatalError
          .ENDIF
          MOV hHuffTabl, EAX
          MOV EDI, EAX
          MOV ESI, lpFreqTabl
          MOV nullCnt, 256
          MOV ECX, 256
          @@:  
            .IF DWORD PTR[ESI]==0
               DEC nullCnt
            .ENDIF
            ADD ESI, 4
            DEC ECX
            JECXZ @F
          JMP @B
          @@:
          MOV EAX, nullCnt
          MOV WORD PTR[EDI], AX    ; HUFFMAN 表的前两字节是元素个数
          MOV ECX, nullCnt
          ADD EDI, 2
          ALIGN DWORD
          .WHILE ECX
              INVOKE FindBiggest,lpFreqTabl
              MOV BYTE PTR[EDI], AL
              MOV DWORD PTR[EDI+1], EBX
              ADD EDI, 5
              DEC ECX
          .ENDW
          POPAD
          MOV EAX, hHuffTabl
          RET
CreatHuffManTabl  ENDP     

HuffManBuild PROC  lpHuffManTabl:DWORD,MODE:DWORD
        LOCAL hTreeHnode:DWORD 
        LOCAL hPtrTmpNode:DWORD 
        LOCAL hHuffCode:DWORD
        LOCAL lpTreeRoot:DWORD
        LOCAL Elems:DWORD
        LOCAL Quene[300]:DWORD  
          PUSHAD      
          LEA EDI, Quene                           ;
          MOV ECX, 260                             ;
          _INIQUENE:                               ;：：初始化堆栈队列指针为NULL，堆栈中垃圾指针会影响 
          JECXZ @F                                 ; 
          MOV DWORD PTR[EDI], NULL                 ; 
          ADD EDI, 4                               ;
          DEC ECX                                  ;
          JMP _INIQUENE                            ;：：循环结束点
          @@:                                      ;
          MOV ESI, lpHuffManTabl                   ; 
          MOVZX EAX, WORD PTR[ESI]                 ; 获取HaffTabl中元素数量
          ADD ESI, 2                               ;  
          MOV Elems, EAX                           ; 保存一下，有用
          ;----------------------------------------------------------------------------
          ; 以下代码是使用HaffTabl初始化 HNODE 数组
          ;----------------------------------------------------------------------------
          .IF alloc(300*SIZEOF HNODE)==NULL        ; 分配内存，其实256*SIZEOF HNODE就够了，但是，有可能出错。
		      PUSH SIGN_ALLOC_FAIL
              CALL FatalError
          .ENDIF                                   ;
          MOV hTreeHnode, EAX                      ; 保存指针
          MOV EDI, hTreeHnode                      ; 设置EDI指向
          MOV EDX, Elems                           ;
          XOR EBX, EBX                             ; EBX用来寻址堆栈队列
          ALIGN DWORD                              ;
          .WHILE EDX                               ;            
              MOV Quene[EBX*4], EDI                ; 保存这个元素的指针到队列
              MOVZX ECX, BYTE PTR[ESI]             ; 获取那个字节
              MOV (HNODE PTR[EDI]).bValue, ECX     ; 写到结构中  
              MOV ECX, DWORD PTR[ESI+1]            ; 获取这个字节的出现频率
              MOV (HNODE PTR[EDI]).weight, ECX     ; 写入到结构
              MOV (HNODE PTR[EDI]).isLeaf, TRUE    ; 设置Leaf标志为真，因为他是存储数据的节点 
              DEC EDX                              ; 
              INC EBX                              ;
              ADD ESI, 5                           ; 
              ADD EDI, SIZEOF HNODE                ;
          .ENDW       
          ;----------------------------------------------------------------------------
          ; 以下代码是通过 已经初始化的HNODE数组 构造哈夫曼树
          ;----------------------------------------------------------------------------
           .IF alloc(300*SIZEOF HNODE)==NULL       ; 分配内存，这么大的原因。。
		   	  PUSH SIGN_ALLOC_FAIL
              CALL FatalError                      ; 这些内存是哈夫曼连接节点，不存储数据
           .ENDIF                                  ; 
           MOV hPtrTmpNode, EAX                    ;
           MOV ESI, hPtrTmpNode                    ;  
           MOV ECX, Elems                          ; 
           .IF ECX==1                              ; 其实这没什么必要，谁没事压缩全是相同字节的文件啊。别说是你！
              MOV EDI, hTreeHnode                  ;
           .ENDIF                                  ; 
           ALIGN DWORD                             ;
           .WHILE ECX > 1                          ; 合并次数为总数据节点数-1次
              MOV EDI, ESI                         ;
              ;----------------------------        ;
              ; 获取一个权最小的元素                ; 说明：在这里获取的是该元素在队列中的地址
              ;----------------------------        ;
              LEA EAX, Quene                       ;
              INVOKE FindSmallest,EAX,Elems        ;
              MOV EDX, [EAX]                       ; 
              MOV DWORD PTR[EAX], NULL             ; 将这个元素的地址从队列删除（设为NULL)
              MOV (HNODE PTR[EDX]).lpParent, EDI   ; 设置元素父节点为EDI
              MOV EBX, (HNODE PTR[EDX]).weight     ; 获取元素的权
              MOV (HNODE PTR[EDI]).lpLeft, EDX     ; 保存到父节点左支
              ;----------------------------        ;
              ; 获取另一个权最小的元素              ;
              ;----------------------------        ;
              LEA EAX, Quene                       ;
              INVOKE FindSmallest,EAX,Elems        ;
              MOV EDX, [EAX]                       ;
              MOV DWORD PTR[EAX], EDI              ; Edi是俩个元素连接节点，将他加入队列（替换掉第二个最小元素）
              MOV (HNODE PTR[EDX]).lpParent, EDI   ; 设置元素父节点为EDI
              ADD EBX, (HNODE PTR[EDX]).weight     ; 计算俩个元素总权值
              MOV (HNODE PTR[EDI]).weight, EBX     ; 写到父节点中
              MOV (HNODE PTR[EDI]).lpRight, EDX    ; 保存到父节点右支
              ADD ESI, SIZEOF HNODE                ;
              DEC ECX                              ;
          .ENDW   
          .IF MODE                                 ; 如果模式是 GET_TREE，返回
              MOV lpTreeRoot, EDI                  ; 
              POPAD
              MOV EAX, lpTreeRoot  
              MOV EBX, hTreeHnode 
              MOV ECX, hPtrTmpNode
              JMP _RET
          .ENDIF
          ;----------------------------------------------------------------------------
          ;  由哈夫曼树生成每个元素的编码    
          ;----------------------------------------------------------------------------
          .IF alloc(SIZEOF HUFFCODE*300)==NULL     ; 分配内存
              PUSH SIGN_ALLOC_FAIL
              CALL FatalError
          .ENDIF                                   ;
          MOV hHuffCode, EAX                       ;
          MOV EDI, EAX                             ;
          MOV EDX, hTreeHnode                      ; EDX指向已经建成树的元素内存块
          MOV ECX, Elems                           ; 
          ALIGN DWORD                              ;
          .WHILE ECX                               ;
             MOV ESI, EDX                          ;                                                        
             MOV EAX, (HNODE PTR[ESI]).bValue      ;  
             MOV (HUFFCODE PTR[EDI]).bValue, EAX   ; 保存该字节值到结构                       
             XOR EAX, EAX                          ; 清零EAX                                              
             ALIGN DWORD                           ;                                                       
             @@:                                   ;
              CMP (HNODE PTR[ESI]).lpParent, NULL  ; 他是根节点吗？（根节点父指针是NULL）                               
              JE  @F                               ; 似的，已完成一个元素的编码构建，转到 @F                          
              MOV EBX, ESI                         ; 保存当前节点指针值，用来比较是在左边还是右边     
              MOV ESI, (HNODE PTR[ESI]).lpParent   ; p=p->Parent                                        
               CMP  EBX, (HNODE PTR[ESI]).lpLeft   ; 将父节点右支和EBX比较       
               JNE  IsRight                        ; 如果相同，那么那个机节点是在父节点左支，否则是右
                  CLC                              ;                                
                  RCR EAX, 1                       ; 在左支，写入位 0                  
                  JMP _NxtParent                   ;                                                   
               IsRight:                            ;                     
                  STC                              ;                                    
                  RCR EAX, 1                       ; 在右支，写入位 1          
              _NxtParent:                          ;                                                  
              INC (HUFFCODE PTR[EDI]).bDepth       ; 增加该编码的深度                          
             JMP @B                                ; 
             @@:                                   ;-----------------------------------------------------------------------------------
             PUSH ECX                              ; 假如一个元素编码是 01001，那么他在 EAX 中是 0100 1000 0000 0000 0000 0000 0000 0000
             MOV ECX, 32                           ; 所以向右移[32-bDepth] 位，那么 EAX 就成了  0000 0000 0000 0000 0000 0000 0000 1001
             SUB ECX, (HUFFCODE PTR[EDI]).bDepth   ; 这段代码不是必要的，但是这个BUG是在我完成整个程序调试时才发现（改一下Compress也行）太懒
             SHR EAX, CL                           ; 就改了这里。。
             POP ECX                               ;-----------------------------------------------------------------------------------                                     
             MOV (HUFFCODE PTR[EDI]).bitVal, EAX   ; 将编码值写入结构
             ADD EDX, SIZEOF HNODE                 ;                                                     
             ADD EDI, SIZEOF HUFFCODE              ;                                                      
             DEC ECX                               ;                                                      
          .ENDW                                    ;
          free(hTreeHnode)                         ;  
          free(hPtrTmpNode)                        ;  
          POPAD                                    ; HUFFCODE结构的内存块需要保留给Compress用
          MOV EAX, hHuffCode                       ; 返回 HUFFCODE结构指针
          MOV EBX, Elems                           ; 返回元素个数
       _RET:
          RET
HuffManBuild ENDP

FindSmallest PROC lpQuene:DWORD,ElemCnt:DWORD
        LOCAL SetNull:DWORD
        PUSHAD 
        MOV ESI, lpQuene
        MOV ECX, ElemCnt
        .WHILE !DWORD PTR[ESI] && ECX    ; 跳过空指针
            ADD ESI, 4
            DEC ECX
        .ENDW 
        MOV EDI, [ESI]
        MOV EAX, (HNODE PTR[EDI]).weight
        MOV SetNull, ESI                 ; 初始化一下
        ADD ESI, 4
        .WHILE ECX 
          .IF DWORD PTR[ESI]             ; 跳过空指针
            MOV EDI, [ESI]               
            MOV EBX, (HNODE PTR[EDI]).weight
            .IF EBX < EAX                ; 如果新元素的权更小
               MOV SetNull, ESI          ; 保存队列指针 
               MOV EAX, EBX              ; 刷新最比较值
            .ENDIF
          .ENDIF
          ADD ESI, 4                   
          DEC ECX                  
        .ENDW
        POPAD 
        MOV EAX, SetNull                 ; 返回队列指针
        RET
FindSmallest ENDP

FindBiggest PROC lpFreqTabl:DWORD
        LOCAL curBiggest:DWORD
        LOCAL index:DWORD
          PUSHAD
          MOV ESI, lpFreqTabl
          MOV EDI, ESI
          MOV index, 0
          MOV EAX, DWORD PTR[ESI]
          MOV curBiggest, EAX
          MOV ECX, 1
          ALIGN DWORD
          @@:  
            ADD ESI, 4
            MOV EAX, DWORD PTR[ESI]
            .IF EAX > curBiggest
               MOV EDI, ESI              
               MOV curBiggest, EAX        
               MOV index, ECX
            .ENDIF
            INC ECX
            CMP ECX, 256
            JE  @F
          JMP @B
         @@:       
          MOV DWORD PTR[EDI], 00h       
          POPAD 
          MOV EAX, index        
          MOV EBX, curBiggest            
          RET
FindBiggest ENDP

MemMove PROC Source:DWORD,Dest:DWORD,Nbyte:DWORD
    PUSHAD
    cld
    mov esi, [Source]
    mov edi, [Dest]
    mov ecx, [Nbyte]
    shr ecx, 2
    rep movsd
    mov ecx, [Nbyte]
    and ecx, 3
    rep movsb
    POPAD
    ret
MemMove endp

FatalError PROC ErrIndex:DWORD
    CALL @F
	;可以自行添加错误信息，但是每个信息长度必须为15字节（包括00h)
	DB 'Fatal Error!  ',00h       ;标题
	DB 'Alloc Failed  ',00h       ;错误信息索引 1
	DB 'Out Of Range  ',00h       ;错误信息索引 2
	DB 'Corrupt File  ',00h       ;错误信息索引 3
	@@:
	POP ESI
	MOV EAX, 15                
	MUL WORD PTR[ErrIndex]
	LEA EDI, [ESI+EAX]
    INVOKE MessageBox,NULL,EDI,ESI,MB_OK
    INVOKE ExitProcess,1
FatalError ENDP

END Starts

