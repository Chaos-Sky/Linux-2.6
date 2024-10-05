# 完全公平算法(CFS)

CFS(完全公平调度器)是在Linux 2.6.23版本中引入的,它的目标是为进程调度提供一个更公平、更高效的机制。以下是CFS的主要设计原理和实现细节:

### 原理

a) 公平性: CFS的核心理念是给每个进程公平的CPU时间。它试图模拟一个"理想的多任务处理器",在这个处理器中,每个进程都能得到相同比例的CPU时间。

b) 虚拟运行时间: CFS引入了"虚拟运行时间"的概念。每个进程都有一个虚拟运行时间,它随着进程实际运行而增加。CFS总是选择虚拟运行时间最小的进程来运行。

c) 权重: 进程可以有不同的优先级(nice值),CFS通过权重来实现这一点。高优先级的进程获得更多的CPU时间,但仍然保持整体的公平性。

d) 红黑树: CFS使用红黑树数据结构来管理可运行进程,这使得插入和查找操作的时间复杂度保持在O(log n)。

### 设计实现

a) 虚拟运行时间计算:
vruntime = actual\_runtime \* (NICE\_0\_LOAD / process\_weight)
其中,NICE\_0\_LOAD是一个常量(通常为1024),process\_weight根据进程的nice值计算。

b) 调度实体(struct sched\_entity):
每个进程都有一个调度实体,包含了vruntime、权重等信息。

c) 红黑树操作:

* 进程变为可运行状态时,根据其vruntime插入红黑树
* 调度时,选择红黑树最左节点(vruntime最小)的进程
* 进程运行后,更新其vruntime并重新插入红黑树

d) 时间片计算:
CFS不使用固定的时间片,而是根据可运行进程数量动态计算。
时间片 ≈ (1 / nr\_running) \* sysctl\_sched\_latency (外部资料，系统版本不确定,参考即可)
其中,nr\_running是可运行进程数,sysctl\_sched\_latency是一个可调参数。

e) 睡眠进程的处理:
当进程从睡眠状态唤醒时,CFS会给予它一定的"补偿",以避免它因长时间睡眠而被饿死。

f) 组调度:
CFS支持组调度,允许将进程分组并在组间进行公平调度。

g) NUMA(Non-Uniform Memory Access)支持:
CFS考虑了NUMA架构,尽量让进程在其内存所在的CPU上运行。

3. 优势:

* 更好的交互性能和响应时间
* 更公平的CPU时间分配
* 可扩展性好,适用于从嵌入式系统到大型服务器
* 算法复杂度低,O(log n)的操作保证了良好的性能

4. 挑战和优化:

* 对于大量短期任务,红黑树操作可能成为瓶颈
* 在某些极端情况下可能出现不公平现象
* 需要细致调优以适应不同的工作负载

## 计算公式

vruntime = actual\_runtime \* (NICE\_0\_LOAD / process\_weight)  更加详细解释

vruntime\_delta = actual\_runtime \* (NICE\_0\_LOAD / process\_weight)
vruntime = previous\_vruntime + vruntime\_delta

## process_weight值为0？

process_weight 不会为0：
在CFS调度器的实现中，process_weight 永远不会为0。这是为了避免除以零的错误，同时也确保每个进程都有机会获得CPU时间。
process_weight 的计算：
process_weight 是根据进程的 nice 值计算得出的。计算公式如下： process_weight = prio_to_weight[nice + 20] 这里的 prio_to_weight是一个预定义的查找表，将 nice 值映射到对应的权重。
prio_to_weight表：
这个表定义了从 nice 值 -20 到 +19 对应的权重值。例如：

```c
/*
 * Nice levels are multiplicative, with a gentle 10% change for every
 * nice level changed. I.e. when a CPU-bound task goes from nice 0 to
 * nice 1, it will get ~10% less CPU time than another CPU-bound task
 * that remained on nice 0.
 *
 * The "10% effect" is relative and cumulative: from _any_ nice level,
 * if you go up 1 level, it's -10% CPU usage, if you go down 1 level
 * it's +10% CPU usage. (to achieve that we use a multiplier of 1.25.
 * If a task goes up by ~10% and another task goes down by ~10% then
 * the relative distance between them is ~25%.)
 */
static const int prio_to_weight[40] = {
 /* -20 */     88761,     71755,     56483,     46273,     36291,
 /* -15 */     29154,     23254,     18705,     14949,     11916,
 /* -10 */      9548,      7620,      6100,      4904,      3906,
 /*  -5 */      3121,      2501,      1991,      1586,      1277,
 /*   0 */      1024,       820,       655,       526,       423,
 /*   5 */       335,       272,       215,       172,       137,
 /*  10 */       110,        87,        70,        56,        45,
 /*  15 */        36,        29,        23,        18,        15,
};

/*
 * Inverse (2^32/x) values of the prio_to_weight[] array, precalculated.
 *
 * In cases where the weight does not change often, we can use the
 * precalculated inverse to speed up arithmetics by turning divisions
 * into multiplications:
 */
static const u32 prio_to_wmult[40] = {
 /* -20 */     48388,     59856,     76040,     92818,    118348,
 /* -15 */    147320,    184698,    229616,    287308,    360437,
 /* -10 */    449829,    563644,    704093,    875809,   1099582,
 /*  -5 */   1376151,   1717300,   2157191,   2708050,   3363326,
 /*   0 */   4194304,   5237765,   6557202,   8165337,  10153587,
 /*   5 */  12820798,  15790321,  19976592,  24970740,  31350126,
 /*  10 */  39045157,  49367440,  61356676,  76695844,  95443717,
 /*  15 */ 119304647, 148102320, 186737708, 238609294, 286331153,
};
```

权重范围：
最小权重：15 (对应 nice 值 +19)
最大权重：88761 (对应 nice 值 -20)
默认权重：1024 (对应 nice 值 0)
权重设计原理：
每个相邻的 nice 值之间的权重比约为 1.25
这意味着 nice 值每改变 1，进程获得的 CPU 时间大约会改变 10%
NICE_0_LOAD：
NICE_0_LOAD 通常定义为 1024，与 nice 值 0 的权重相对应。
vruntime 计算：
使用这些权重，vruntime 的增加率会根据进程的优先级（nice 值）而变化：
高优先级（低 nice 值）的进程，其 vruntime 增加得较慢
低优先级（高 nice 值）的进程，其 vruntime 增加得较快
实际应用：
在实际的内核实现中，为了提高效率，这些计算通常会使用整数算术和位移操作，而不是浮点数运算。
动态调整：
虽然基本权重是预定义的，但 CFS 调度器可以根据系统负载和其他因素动态调整实际使用的权重。

## 如何分配合理时间？(思考)

提示：1.进程和线程都是task_struct,CPU以线程为调度单位

如果有一个多人游戏(具备反外挂)，多线程情况下(多个Task_struct)采用CFS调度算法，如何更好的分配CPU时间(NICE)，提升游戏性能？
