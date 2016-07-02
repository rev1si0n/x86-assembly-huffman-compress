
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
      MOV hHuffCode, EAX               ; ����ָ��HUFFCODE�ṹ��ָ�뷵��ֵ
      MOV Elems, EBX                   
      MOV ESI, lpData
      MOV EDI, lpBuf     
      MOV EBX, hHuffTabl    
      MOV EAX, dSize
	  MOV WORD PTR[EDI],'DE'           ; �ļ�ͷ 'ED' ��־ @_@
      MOV DWORD PTR[EDI+2], EAX        ; д�����ֽ�ԭʼ���ݴ�С��������                                                               
      ADD EDI, 6      
      MOVZX EAX, WORD PTR[EBX]
      MOV WORD PTR[EDI], AX            ; д�����ֽ�HUFFMAN��Ԫ�ظ�����������  
      ADD EBX, 2           
      ADD EDI, 2             
      MOV CX, 5                  
      MUL CX                         
      PUSH EAX
      PUSH EDI
      PUSH EBX
      CALL MemMove                     ; д��HUFFMAN��������[����*5 Bytes] 
      ADD EDI, EAX                     ; ����ָ��ָ�򻺳����е�������
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
        .IF ECX > bDepth            ; ����ñ��볤��С��EAXʣ��ɴ���λ
           SUB ECX, bDepth          ; ������λ�� 
           SHL bitVal, CL           ; 
           XOR EAX, bitVal          ; ���ñ������EAX
        .ELSE                      
           SUB bDepth, ECX           ; �����и�λ��ֻд��EAX���ɴ��λ��ʣ��λ�����´�    **|| ���� ���ĸ������� 01 101 11 1100 ��һ��8λ�Ĵ洢��ֻ���Դ���8λ���루�������Ǽ���,EAX��32λ�ģ�
           MOV ECX, bDepth           ; ������λ��������λ��������߿�дλ������д��λ�ݴ�EBX  || �洢���Ѵ���ǰ��������0110 111x������һλû�ã����ǵ��ĸ�������4λ������ֻ�ܴ�һλ��
           PUSH ECX                  ;                                                        || ���ԣ�����ߵ�λ1����洢����������ʣ������λ100��Ȼ��Ѵ洢�����Ѿ�ʢ���ı���д�뻺������
           @@:                       ;                                                        || ֱ��������һ�Σ�����ȡ��һ���ֽڵı��룬��Ϊ������һ�����뻹����λû����ô��
           JECXZ _Out
           SHR bitVal, 1             ; ֻ�����ɴ���EAX�����λ
           RCR EBX, 1                ; �����ɴ���ݴ��� EBX
           DEC ECX                    
           JMP @B
          _Out:
           POP ECX  
	       XOR EAX, bitVal          
           MOV [EDI], EAX            ; �ﵽ�˲� EAX ��32��λ�Ѵ����� д�뻺����
           ADD EDI, 4 
           XOR EAX, EAX              ; EAX ���㣬׼���´�             
           .IF ECX                   
             ROL EBX, CL             ; ��ʣ��λ��������λ
             MOV bitVal, 0           
             XOR bitVal, EBX         ; ��ʣ��λ����  bitVal 
             XOR ECX, ECX            
             JMP _WRITEBIT           ; �ٴδ���
           .ENDIF
         .ENDIF
         INC ESI
         DEC dSize
      .ENDW
      .IF ECX                        ; ���ѭ����������ֵ�� EAX ��
	 MOV [EDI], EAX                  ; д��
	 ADD EDI, 4
      .ENDIF
      free(hHuffCode)
      free(hHuffTabl)
      free(hFreqTabl)
      SUB EDI, lpBuf
      MOV BWrite, EDI                ; ���һ��д���ָ��-��������ָ�� = д����ֽ���
      POPAD
      MOV EAX, BWrite                ; ����д�뻺�������ֽ���
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
	  .IF WORD PTR[ESI]!='DE'                  ; �����ļ�ͷ1-2��־�ֽڣ��������'ED'��ô�ⲻ��Compress�������ļ�
	     PUSH SIGN_INVALID
		 CALL FatalError
	  .ENDIF
      MOV EAX, [ESI+2]                         ; ��ȡ��ѹ�����ݵĵ�3-6�ֽ�(�����ֽ���ԭʼδѹ�����ݵĴ�С)
      MOV RawSize, EAX                         ; �洢������ RawSize
	  ADD ESI, 6                               ; ��־�ֽڣ�2��+ԭʼ�ļ���С��4�� =6
      INVOKE HuffManBuild,ESI,GET_TREE         ; �Ӻ����л�ȡһ����������ESIָ�������ֽ�
      MOV lpTreeRoot, EAX
      MOV hNodes, EBX
      MOV hTreeNodes, ECX                      ; �洢һ��
      MOVZX EAX, WORD PTR[ESI]                 ; ��ȡ��5��6�ֽڣ������ֽ��ǽ�������HaffTabl��Ԫ��������
      ADD ESI, 2                                
      MOV CX, 5
      MUL CX                                   ; ��Ԫ������*5������Ҫ��ȡ��HuffTable��С
      ADD ESI, EAX                             ; ����HuffTable��С����ô����ESIָ��������ݶ�
      MOV EBX, lpTreeRoot                      ; ��ʼ��һ��EBX

     _NEXT:
      MOV EAX, [ESI]                           ; ��ȡ4���ֽڵı���
      MOV ECX, 32                              ; ������λ����EAX ��32λ��
     _AGAIN:
      .WHILE ECX                                
        SHL EAX, 1                             ; ����һλ
        JNC _LEFT
           MOV EBX, (HNODE PTR[EBX]).lpRight   ; �н�λ��ת�򸸽ڵ���֧
           JMP _IFOUT
         _LEFT:
           MOV EBX, (HNODE PTR[EBX]).lpLeft    ; �޽�λ��ת�򸸽ڵ���֧
        _IFOUT:  
        DEC ECX
        CMP (HNODE PTR[EBX]).isLeaf, TRUE      ; ����һ���洢���ݵ�HNODE ��
        JE _FOUND                              ; �Ƶģ�ת��_FOUND
      .ENDW
      JMP @F                                   ; ���򣬶�ȡ��һ��4�ֽڹ���������
      _FOUND:
       MOV EDX, (HNODE PTR[EBX]).bValue        ; ��ȡ�ڵ��д洢��ֵ
       MOV [EDI], DL                           ; д�뻺����
       INC EDI
       MOV EBX, lpTreeRoot                     ; ���� EBX ָ����ڵ�
       DEC RawSize                             
       .IF !RawSize                            ; ���д���ֽ�����ԭʼ��С��ͬ����ô��ɣ�
          JMP _OK               
       .ENDIF
       .IF ECX                                 ; ���ECX��Ϊ0��˵��ǰһ��EAX�л���δ��ȡ�Ĺ�����λ
         JMP _AGAIN                            ; ����һ�Σ��˴β�������EBX
       .ENDIF
     @@:
       ADD ESI, 4                              ; ָ����һ��4�ֽڹ���������
       JMP _NEXT
     _OK:
      XCHG EDI, lpBuf                          ; �ⲽ������������д���ֽ����ģ�
      SUB lpBuf, EDI                           ; lpBufָ���ʼ��ַ��EDI�����д��ĵ�ַ�����Խ����������Ϊ��д���ֽ�����
      free(hNodes)
      free(hTreeNodes) 
      POPAD                                   
      MOV EAX, lpBuf                           ; д�뷵��ֵ
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
 ; ���´����ռ��ֽڳ���Ƶ��
        @@:
          MOVZX EAX, BYTE PTR[ESI]
          INC DWORD PTR[EDI+EAX*4]
          INC ESI
          DEC ECX
          JECXZ @F 
          JMP @B
 ; ���´��빹�� HUFFMAN �� δ���ֵ��ֽڽ�������
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
          MOV WORD PTR[EDI], AX    ; HUFFMAN ���ǰ���ֽ���Ԫ�ظ���
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
          _INIQUENE:                               ;������ʼ����ջ����ָ��ΪNULL����ջ������ָ���Ӱ�� 
          JECXZ @F                                 ; 
          MOV DWORD PTR[EDI], NULL                 ; 
          ADD EDI, 4                               ;
          DEC ECX                                  ;
          JMP _INIQUENE                            ;����ѭ��������
          @@:                                      ;
          MOV ESI, lpHuffManTabl                   ; 
          MOVZX EAX, WORD PTR[ESI]                 ; ��ȡHaffTabl��Ԫ������
          ADD ESI, 2                               ;  
          MOV Elems, EAX                           ; ����һ�£�����
          ;----------------------------------------------------------------------------
          ; ���´�����ʹ��HaffTabl��ʼ�� HNODE ����
          ;----------------------------------------------------------------------------
          .IF alloc(300*SIZEOF HNODE)==NULL        ; �����ڴ棬��ʵ256*SIZEOF HNODE�͹��ˣ����ǣ��п��ܳ���
		      PUSH SIGN_ALLOC_FAIL
              CALL FatalError
          .ENDIF                                   ;
          MOV hTreeHnode, EAX                      ; ����ָ��
          MOV EDI, hTreeHnode                      ; ����EDIָ��
          MOV EDX, Elems                           ;
          XOR EBX, EBX                             ; EBX����Ѱַ��ջ����
          ALIGN DWORD                              ;
          .WHILE EDX                               ;            
              MOV Quene[EBX*4], EDI                ; �������Ԫ�ص�ָ�뵽����
              MOVZX ECX, BYTE PTR[ESI]             ; ��ȡ�Ǹ��ֽ�
              MOV (HNODE PTR[EDI]).bValue, ECX     ; д���ṹ��  
              MOV ECX, DWORD PTR[ESI+1]            ; ��ȡ����ֽڵĳ���Ƶ��
              MOV (HNODE PTR[EDI]).weight, ECX     ; д�뵽�ṹ
              MOV (HNODE PTR[EDI]).isLeaf, TRUE    ; ����Leaf��־Ϊ�棬��Ϊ���Ǵ洢���ݵĽڵ� 
              DEC EDX                              ; 
              INC EBX                              ;
              ADD ESI, 5                           ; 
              ADD EDI, SIZEOF HNODE                ;
          .ENDW       
          ;----------------------------------------------------------------------------
          ; ���´�����ͨ�� �Ѿ���ʼ����HNODE���� �����������
          ;----------------------------------------------------------------------------
           .IF alloc(300*SIZEOF HNODE)==NULL       ; �����ڴ棬��ô���ԭ�򡣡�
		   	  PUSH SIGN_ALLOC_FAIL
              CALL FatalError                      ; ��Щ�ڴ��ǹ��������ӽڵ㣬���洢����
           .ENDIF                                  ; 
           MOV hPtrTmpNode, EAX                    ;
           MOV ESI, hPtrTmpNode                    ;  
           MOV ECX, Elems                          ; 
           .IF ECX==1                              ; ��ʵ��ûʲô��Ҫ��˭û��ѹ��ȫ����ͬ�ֽڵ��ļ�������˵���㣡
              MOV EDI, hTreeHnode                  ;
           .ENDIF                                  ; 
           ALIGN DWORD                             ;
           .WHILE ECX > 1                          ; �ϲ�����Ϊ�����ݽڵ���-1��
              MOV EDI, ESI                         ;
              ;----------------------------        ;
              ; ��ȡһ��Ȩ��С��Ԫ��                ; ˵�����������ȡ���Ǹ�Ԫ���ڶ����еĵ�ַ
              ;----------------------------        ;
              LEA EAX, Quene                       ;
              INVOKE FindSmallest,EAX,Elems        ;
              MOV EDX, [EAX]                       ; 
              MOV DWORD PTR[EAX], NULL             ; �����Ԫ�صĵ�ַ�Ӷ���ɾ������ΪNULL)
              MOV (HNODE PTR[EDX]).lpParent, EDI   ; ����Ԫ�ظ��ڵ�ΪEDI
              MOV EBX, (HNODE PTR[EDX]).weight     ; ��ȡԪ�ص�Ȩ
              MOV (HNODE PTR[EDI]).lpLeft, EDX     ; ���浽���ڵ���֧
              ;----------------------------        ;
              ; ��ȡ��һ��Ȩ��С��Ԫ��              ;
              ;----------------------------        ;
              LEA EAX, Quene                       ;
              INVOKE FindSmallest,EAX,Elems        ;
              MOV EDX, [EAX]                       ;
              MOV DWORD PTR[EAX], EDI              ; Edi������Ԫ�����ӽڵ㣬����������У��滻���ڶ�����СԪ�أ�
              MOV (HNODE PTR[EDX]).lpParent, EDI   ; ����Ԫ�ظ��ڵ�ΪEDI
              ADD EBX, (HNODE PTR[EDX]).weight     ; ��������Ԫ����Ȩֵ
              MOV (HNODE PTR[EDI]).weight, EBX     ; д�����ڵ���
              MOV (HNODE PTR[EDI]).lpRight, EDX    ; ���浽���ڵ���֧
              ADD ESI, SIZEOF HNODE                ;
              DEC ECX                              ;
          .ENDW   
          .IF MODE                                 ; ���ģʽ�� GET_TREE������
              MOV lpTreeRoot, EDI                  ; 
              POPAD
              MOV EAX, lpTreeRoot  
              MOV EBX, hTreeHnode 
              MOV ECX, hPtrTmpNode
              JMP _RET
          .ENDIF
          ;----------------------------------------------------------------------------
          ;  �ɹ�����������ÿ��Ԫ�صı���    
          ;----------------------------------------------------------------------------
          .IF alloc(SIZEOF HUFFCODE*300)==NULL     ; �����ڴ�
              PUSH SIGN_ALLOC_FAIL
              CALL FatalError
          .ENDIF                                   ;
          MOV hHuffCode, EAX                       ;
          MOV EDI, EAX                             ;
          MOV EDX, hTreeHnode                      ; EDXָ���Ѿ���������Ԫ���ڴ��
          MOV ECX, Elems                           ; 
          ALIGN DWORD                              ;
          .WHILE ECX                               ;
             MOV ESI, EDX                          ;                                                        
             MOV EAX, (HNODE PTR[ESI]).bValue      ;  
             MOV (HUFFCODE PTR[EDI]).bValue, EAX   ; ������ֽ�ֵ���ṹ                       
             XOR EAX, EAX                          ; ����EAX                                              
             ALIGN DWORD                           ;                                                       
             @@:                                   ;
              CMP (HNODE PTR[ESI]).lpParent, NULL  ; ���Ǹ��ڵ��𣿣����ڵ㸸ָ����NULL��                               
              JE  @F                               ; �Ƶģ������һ��Ԫ�صı��빹����ת�� @F                          
              MOV EBX, ESI                         ; ���浱ǰ�ڵ�ָ��ֵ�������Ƚ�������߻����ұ�     
              MOV ESI, (HNODE PTR[ESI]).lpParent   ; p=p->Parent                                        
               CMP  EBX, (HNODE PTR[ESI]).lpLeft   ; �����ڵ���֧��EBX�Ƚ�       
               JNE  IsRight                        ; �����ͬ����ô�Ǹ����ڵ����ڸ��ڵ���֧����������
                  CLC                              ;                                
                  RCR EAX, 1                       ; ����֧��д��λ 0                  
                  JMP _NxtParent                   ;                                                   
               IsRight:                            ;                     
                  STC                              ;                                    
                  RCR EAX, 1                       ; ����֧��д��λ 1          
              _NxtParent:                          ;                                                  
              INC (HUFFCODE PTR[EDI]).bDepth       ; ���Ӹñ�������                          
             JMP @B                                ; 
             @@:                                   ;-----------------------------------------------------------------------------------
             PUSH ECX                              ; ����һ��Ԫ�ر����� 01001����ô���� EAX ���� 0100 1000 0000 0000 0000 0000 0000 0000
             MOV ECX, 32                           ; ����������[32-bDepth] λ����ô EAX �ͳ���  0000 0000 0000 0000 0000 0000 0000 1001
             SUB ECX, (HUFFCODE PTR[EDI]).bDepth   ; ��δ��벻�Ǳ�Ҫ�ģ��������BUG��������������������ʱ�ŷ��֣���һ��CompressҲ�У�̫��
             SHR EAX, CL                           ; �͸��������
             POP ECX                               ;-----------------------------------------------------------------------------------                                     
             MOV (HUFFCODE PTR[EDI]).bitVal, EAX   ; ������ֵд��ṹ
             ADD EDX, SIZEOF HNODE                 ;                                                     
             ADD EDI, SIZEOF HUFFCODE              ;                                                      
             DEC ECX                               ;                                                      
          .ENDW                                    ;
          free(hTreeHnode)                         ;  
          free(hPtrTmpNode)                        ;  
          POPAD                                    ; HUFFCODE�ṹ���ڴ����Ҫ������Compress��
          MOV EAX, hHuffCode                       ; ���� HUFFCODE�ṹָ��
          MOV EBX, Elems                           ; ����Ԫ�ظ���
       _RET:
          RET
HuffManBuild ENDP

FindSmallest PROC lpQuene:DWORD,ElemCnt:DWORD
        LOCAL SetNull:DWORD
        PUSHAD 
        MOV ESI, lpQuene
        MOV ECX, ElemCnt
        .WHILE !DWORD PTR[ESI] && ECX    ; ������ָ��
            ADD ESI, 4
            DEC ECX
        .ENDW 
        MOV EDI, [ESI]
        MOV EAX, (HNODE PTR[EDI]).weight
        MOV SetNull, ESI                 ; ��ʼ��һ��
        ADD ESI, 4
        .WHILE ECX 
          .IF DWORD PTR[ESI]             ; ������ָ��
            MOV EDI, [ESI]               
            MOV EBX, (HNODE PTR[EDI]).weight
            .IF EBX < EAX                ; �����Ԫ�ص�Ȩ��С
               MOV SetNull, ESI          ; �������ָ�� 
               MOV EAX, EBX              ; ˢ����Ƚ�ֵ
            .ENDIF
          .ENDIF
          ADD ESI, 4                   
          DEC ECX                  
        .ENDW
        POPAD 
        MOV EAX, SetNull                 ; ���ض���ָ��
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
	;����������Ӵ�����Ϣ������ÿ����Ϣ���ȱ���Ϊ15�ֽڣ�����00h)
	DB 'Fatal Error!  ',00h       ;����
	DB 'Alloc Failed  ',00h       ;������Ϣ���� 1
	DB 'Out Of Range  ',00h       ;������Ϣ���� 2
	DB 'Corrupt File  ',00h       ;������Ϣ���� 3
	@@:
	POP ESI
	MOV EAX, 15                
	MUL WORD PTR[ErrIndex]
	LEA EDI, [ESI+EAX]
    INVOKE MessageBox,NULL,EDI,ESI,MB_OK
    INVOKE ExitProcess,1
FatalError ENDP

END Starts

