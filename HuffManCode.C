//-----------------------------------------------------
// Coded By ZhangYiDa
//-----------------------------------------------------
#include<stdio.h>
#include<stdlib.h>
#include<string.h>
#include<windows.h>
#define  GET_TREE  (1)
#define  GET_CODE  (0)
//使用两个WIN32函数
#define  hFree(hMem) HeapFree(GetProcessHeap(), HEAP_NO_SERIALIZE + HEAP_ZERO_MEMORY, hMem)
#define  hAlloc(bSize) HeapAlloc(GetProcessHeap(), HEAP_NO_SERIALIZE + HEAP_ZERO_MEMORY, bSize)
//重要结构的解释都在<compress.inc>文件中
struct HNODE{
	unsigned  weight;
	unsigned  isLeaf;
	unsigned char bValue;
	void*lpParent;
	void*lpLeft;
	void*lpRight;
};
struct HUFFCODE{
	unsigned char bValue;
	unsigned char bDepth;
	unsigned  bitVal;
};
struct SUITELEM{
	unsigned char sByte;
	unsigned  sFreq;
};
struct HUFFTABL{
	unsigned tablElems;
	struct SUITELEM elem[256];
};
//C不能一次返回几个值，只能自定义一个结构返回
struct POINTERS{     
	void*p1;        
	void*p2;
	void*p3;
};

int FindBiggest(unsigned*,void*);
struct POINTERS HuffManBuild(void*, int);
void* CreatHuffManTabl(void*, unsigned);
int FindSmallest(unsigned*, unsigned);
//unsigned Compress(void*, void*, unsigned);
void FailAlloc(void);
void RCR(unsigned*, unsigned);
/*
 *        因为本程序的寻址纯粹是地址值相加来计算结构偏移而不是C数组索引方式，所以结构指针的声明不应该是 struct XXX aaa，这样会寻错地址
 *        如果这样声明，计算结果不是n*sizeof(struct xx)而是structXX[n+n*sizeof(struct xx)],结果差一大截，所以程序中声明都是 void*xxx
 *        不要问我为什么这么麻烦，（好几个月没碰C，其实是我连数组都不会用了<_<、），我是在DEBUG时发现n*sizeof(struct HUFFCODE)应该是n*8
 *        偏移却被算成了n*8*8，后来想想，原来是声明搞得鬼。还有就是我只是一个初学者，注释恐怕只有我自己能看懂，哎~
 *        ************************************************************************************************************************
 *        以下 MAIN（） 部分的代码用于测试哈夫曼编码生成
*/
int main(void){
	unsigned Carry,index,lineCnt;
	void*lpHc;
	struct POINTERS x;          //这个结构用来接收返回值
	char test[500];
	puts("Enter A String [English]:");
	gets(test); 
	x = HuffManBuild(CreatHuffManTabl(test, strlen(test)),GET_CODE);
	printf("共有不重复字节%3d个\n",(int)x.p2);
	lineCnt = (unsigned)x.p2;	   //虽然x.p2是一个VOID指针，但是循环是可以得，毕竟它也是一个数值
	for (index = 0; lineCnt;index++,lineCnt--)
	{   //外循环输出基本信息
		lpHc = (void*)x.p1 + index*sizeof(struct HUFFCODE);
		printf("值=%3d |  编码长度=%2d | 编码 = ", (*(struct HUFFCODE*)lpHc).bValue,(*(struct HUFFCODE*)lpHc).bDepth);
		Carry = (unsigned)1 << ((*(struct HUFFCODE*)lpHc).bDepth - 1);        //如果编码长度bDepth是5，那么需要从第四位开始测试（二进制位和数组一样，从0开始）
		while ((*(struct HUFFCODE*)lpHc).bDepth--)
		{   //内循环输出编码
			putchar(((*(struct HUFFCODE*)lpHc).bitVal & Carry) ? '1' : '0');  //如果对应位是1则输出1，是0则输出0
			Carry >>= 1;                                                      //Carry右移1位，准备检测下一位
		}  
		putchar('\n');  //换行输出下一组信息
	}
	getchar();
	return 0;
}

struct POINTERS HuffManBuild(void*lpHuffTabl, int MODE)
{
	unsigned Quene[300] = { 0 };   	//队列，存放每个[存放数据的HNODE节点]的地址
	//其实在Win32程序里unsigned和指针同样都是32位的值，因为指针本来也是值，所以可以存储在unsigned数组中（随便什么类型，只要是32位就行，像void*,int*这些指针数组也可以）
	unsigned offset,totWeight;
	unsigned indexQE, indexSE,indexHN,elemCnt,eCnt;
	void*lpHnode, *lpTmpHnode, *RootPtr;   //lpTmpHnode是指向哈夫曼树（连接节点数组）的指针，lpHnode是指向哈夫曼树（数据节点数组）的指针
	void*hSeek,*tmphSeek;
	void*lpHuffCode;                       
	struct POINTERS iPointer;
	if ((lpHnode = hAlloc(300 * sizeof(struct HNODE))) == NULL)	FailAlloc();  //使用WIN32函数主要为了方便，直接全0内存块，不然Malloc还要初始化
	//indexQE  索引队列
	//indexSE  索引HUFFTABL中的SUITELEM结构数组
	//indexHN  索引HNODE结构数组
	eCnt = elemCnt = (*(struct HUFFTABL*)lpHuffTabl).tablElems;             //获取表中元素个数
	for (indexQE = 0, indexSE = 0, indexHN = 0; eCnt>0; eCnt--, indexSE++,indexHN++)
	{
		Quene[indexQE++] = (unsigned)lpHnode + indexHN*sizeof(struct HNODE);   //每一个HNODE元素的地址等于 HNODE内存块基指针+元素索引*一个元素占有的字节数，这样或许不用每一次都来个Malloc()。
		((struct HNODE*)lpHnode)[indexHN].bValue = (*(struct HUFFTABL*)lpHuffTabl).elem[indexSE].sByte;
		((struct HNODE*)lpHnode)[indexHN].weight = (*(struct HUFFTABL*)lpHuffTabl).elem[indexSE].sFreq;
		((struct HNODE*)lpHnode)[indexHN].lpLeft = NULL;            
		((struct HNODE*)lpHnode)[indexHN].lpRight = NULL;           
		((struct HNODE*)lpHnode)[indexHN].lpParent = NULL;            
		((struct HNODE*)lpHnode)[indexHN].isLeaf = TRUE;           //设置是否为数据节点（真）
	}
	//以下部分主要为哈夫曼树的建造
	if ((lpTmpHnode = hAlloc(300 * sizeof(struct HNODE))) == NULL) FailAlloc(); //这里分配一个HNODE数组【300】
	//eCnt = elemCnt  循环计数
	//eCnt > 1        合并次数=元素总数-1次
	//offset=0        主要用于计算RootPtr（每次结果都会比原指针大sizeof(struct HNODE)个字节），相当于索引
	for (eCnt = elemCnt, offset = 0; eCnt > 1; offset++, eCnt--)
	{
		RootPtr = (void*)lpTmpHnode + offset*sizeof(struct HNODE);   //这一步从节点HNODE块获取一个节点HNODE指针,上面说过用法。
		indexQE=FindSmallest(Quene, elemCnt);                        //从队列中获取一个最小权元素索引
		(*(struct HNODE*)Quene[indexQE]).lpParent = (void*)RootPtr;  //设置元素父节点
		totWeight = (*(struct HNODE*)Quene[indexQE]).weight;         //保存一下这元素的权值
		(*(struct HNODE*)RootPtr).lpLeft = (void*)Quene[indexQE];    //设置元素父节点
		Quene[indexQE] = 0;                                          //将这个元素从队列移除，置0的话就会被FindSmallest跳过
		indexQE = FindSmallest(Quene, elemCnt);                      //从队列获取另一个最小权元素
		(*(struct HNODE*)Quene[indexQE]).lpParent = (void*)RootPtr;  //设置元素父节点
		totWeight += (*(struct HNODE*)Quene[indexQE]).weight;        //求俩个最小权元素的权值
		(*(struct HNODE*)RootPtr).lpRight = (void*)Quene[indexQE];   //将元素连接到父节点右支
		(*(struct HNODE*)RootPtr).lpParent = NULL;                   //设置连接节点父节点为空
		(*(struct HNODE*)RootPtr).weight = totWeight;                //将俩个最小权元素的权写入父节点
		(*(struct HNODE*)RootPtr).isLeaf = FALSE;                    //连接节点非数据节点
		Quene[indexQE] = (unsigned)RootPtr;                         //将新合并的节点加入队列
	}
	//如果是GET_TREE模式，那么返回一棵树 
	if (MODE)            
	{
		iPointer.p1 = (void*)RootPtr;                                //RootPtr指向根节点
		iPointer.p2 = (void*)lpTmpHnode;                             //这俩个主要是为释放内存，因为树还没有用，暂时不能释放。
		iPointer.p3 = (void*)lpHnode;                             
		return iPointer;
	}
	//分配HUFFCODE结构数组内存块
	if ((lpHuffCode = hAlloc(300 * sizeof(struct HUFFCODE))) == NULL) FailAlloc();
	for (offset = 0, indexHN = 0, eCnt = elemCnt; eCnt--; indexHN++, offset++)
	{
		hSeek = (void*)lpHnode + indexHN*sizeof(struct HNODE);
		(*(struct HUFFCODE*)(lpHuffCode + offset*sizeof(struct HUFFCODE))).bValue = (*(struct HNODE*)hSeek).bValue;
		while ((*(struct HNODE*)hSeek).lpParent)
		{
			tmphSeek = hSeek;                                  //保存指针用于比较在左边还是右边
			hSeek = (*(struct HNODE*)hSeek).lpParent;          //p=p->next;
			if ((*(struct HNODE*)hSeek).lpLeft == tmphSeek)
			{   //在左边，写入0
				RCR(&((*(struct HUFFCODE*)(lpHuffCode + offset*sizeof(struct HUFFCODE))).bitVal), 0);
			}
			else
			{   //在右边，写入1
				RCR(&((*(struct HUFFCODE*)(lpHuffCode + offset*sizeof(struct HUFFCODE))).bitVal), 1);
			}
			++(*(struct HUFFCODE*)(lpHuffCode + offset*sizeof(struct HUFFCODE))).bDepth;  //编码长度++
		}
		(*(struct HUFFCODE*)(lpHuffCode + offset*sizeof(struct HUFFCODE))).bitVal >>= (32 - (*(struct HUFFCODE*)(int)(lpHuffCode + offset*sizeof(struct HUFFCODE))).bDepth);
	}
	iPointer.p1 = (void*)lpHuffCode;                                               //返回HUFFCODE数组指针
	iPointer.p2 = (void*)elemCnt;                                                  //返回元素个数（这是可以得）
	hFree(lpTmpHnode);
	hFree(lpHnode);
	return iPointer;
}
//RCR函数的作用是，给定一个unsigned(dest)值，给定一个开关标志 0 or 1（flag)，将这个标志位移位到到该值的最左边一位
//假如一个值 iVal=8（二进制 0000 1000），这样调用RCR(&iVal,1),那么iVal结果是 132（二进制1000 0100）
void RCR(unsigned*dest, unsigned flag)
{
	*dest >>= 1;
	*dest |= (flag << 31);
}

void* CreatHuffManTabl(void*lpData, unsigned bCnt)
{
	unsigned tmpCnt = 0;
	unsigned validCnt, index;
	unsigned*lpFreqTabl;
	void*lpHuffTabl;
	struct SUITELEM iSuit;
	if ((lpFreqTabl = hAlloc(300 * sizeof( unsigned))) == NULL) FailAlloc();
	if ((lpHuffTabl = hAlloc(sizeof(struct HUFFTABL))) == NULL) FailAlloc();
	while (tmpCnt++<bCnt) index = *(unsigned char*)lpData++, lpFreqTabl[index]++;
	//从数据区获取一个字节作为索引，并指向下一个字节
    //假如该字节是126，那么字节126的出现频率加 1
	for (validCnt = 256, index = 255; index !=(unsigned)-1; index--)
	{
		if (!lpFreqTabl[index])
			--validCnt;         //如果该字节对应的频率为0，那么这个字节未出现过，舍弃
	}
	(*(struct HUFFTABL*)lpHuffTabl).tablElems = validCnt;
	for (index = 0; validCnt ; validCnt--)
	{
		FindBiggest(lpFreqTabl, &iSuit);
		(*(struct HUFFTABL*)lpHuffTabl).elem[index++] = iSuit;
	}
	hFree(lpFreqTabl);
	return lpHuffTabl;

}
int FindBiggest(unsigned*lpFreqTabl, void*lpSuitByte)
{
	unsigned forComp,suitByte = 0;
	int index = 0;
	for (forComp = lpFreqTabl[index++]; index < 256; index++)
	{
		if (lpFreqTabl[index]>forComp)
		{
			forComp = lpFreqTabl[index];
			suitByte = index;
		}
	}
	(*(struct SUITELEM*)lpSuitByte).sByte = suitByte;
	(*(struct SUITELEM*)lpSuitByte).sFreq = forComp;
	lpFreqTabl[suitByte] = 0;
	return 0;
}

int FindSmallest(unsigned*lpQuene, unsigned elemCnt)
{
	unsigned index = 0;
	unsigned setNull;
	unsigned forComp;
	while (!lpQuene[index] && elemCnt) index++,elemCnt--;
	forComp = (*(struct HNODE*)lpQuene[index]).weight;
	setNull = index++;
	while (elemCnt--)
	{
		if (lpQuene[index])
		{
			if (forComp > ((*(struct HNODE*)lpQuene[index]).weight))
			{
				forComp = (*(struct HNODE*)lpQuene[index]).weight;
				setNull = index;
			}
		}
	    ++index;
	}
	return setNull;
}
void FailAlloc(void)
{
	puts("Mem Alloc Failed!");
	exit(EXIT_FAILURE);
}






