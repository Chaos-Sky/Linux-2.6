# Exit()函数内核实现

1. ```c
   /*
    * this kills every thread in the thread group. Note that any externally
    * wait4()-ing process will get the correct exit code - even if this
    * thread is not the thread group leader.
    */
   SYSCALL_DEFINE1(exit_group, int, error_code)
   {
   	do_group_exit((error_code & 0xff) << 8);
   	/* NOTREACHED */
   	return 0;
   }
   ```
2. ```c
   /*
    * Take down every thread in the group.  This is called by fatal signals
    * as well as by sys_exit_group (below).
    */
   NORET_TYPE void
   do_group_exit(int exit_code)
   {
   	struct signal_struct *sig = current->signal;

   	BUG_ON(exit_code & 0x80); /* core dumps don't get here */

   	if (signal_group_exit(sig)) // 调用 signal_group_exit(sig) 函数判断当前信号是否表示线程组退出。如果是，直接将 exit_code 设置为 sig->group_exit_code。
   		exit_code = sig->group_exit_code;
   	else if (!thread_group_empty(current)) { //如果当前线程组不为空，则进入下一步。这意味着当前进程下还有其他线程在运行。
   		struct sighand_struct *const sighand = current->sighand;
   		spin_lock_irq(&sighand->siglock); //自旋锁
   		if (signal_group_exit(sig)) //在获得锁后，再次检查 signal_group_exit(sig)。如果此时返回为真，说明在当前线程获得锁之前，已经有其他线程处理了退出信号，则更新 exit_code。
   			/* Another thread got here before we took the lock.  */
   			exit_code = sig->group_exit_code;
   		else {
   			sig->group_exit_code = exit_code;
   			sig->flags = SIGNAL_GROUP_EXIT;
   			zap_other_threads(current); //杀死当前进程下的所有的线程
   		}
   		spin_unlock_irq(&sighand->siglock);
   	}

   	do_exit(exit_code); //退出执行核心函数
   	/* NOTREACHED */
   }
   ```
3. ```c
    NORET_TYPE void do_exit(long code)
   {
   	struct task_struct *tsk = current;
   	int group_dead;

   	profile_task_exit(tsk); //在任务退出时被调用，用于记录或更新与该任务相关的性能指标。

   	WARN_ON(atomic_read(&tsk->fs_excl));

   	if (unlikely(in_interrupt())) //in_interrupt() 是一个函数，检查当前是否处于中断上下文中。中断上下文是指在中断处理程序中运行的状态。如果当前处于中断上下文，调用 panic 函数，输出错误信息并导致内核崩溃。
   		panic("Aiee, killing interrupt handler!");
   	if (unlikely(!tsk->pid)) //如果 tsk->pid 为零，表示试图结束空闲任务（idle task），这也是不可接受的。调用 panic 函数输出错误信息并导致内核崩溃。
   		panic("Attempted to kill the idle task!");

   	tracehook_report_exit(&code); //tracehook_report_exit(&code); 可能用于记录或追踪任务退出的事件，code 是退出代码或状态。

   	validate_creds_for_do_exit(tsk); //validate_creds_for_do_exit(tsk); 函数用于验证当前任务是否有权执行退出操作。它确保任务在退出时符合权限要求，防止不当的退出行为。

   	/*
   	 * We're taking recursive faults here in do_exit. Safest is to just
   	 * leave this task alone and wait for reboot.
   	 */ //这段注释说明在 do_exit 函数中遇到了递归故障。在这种情况下，最安全的做法是让该任务保持不变，并等待系统重启。
   	if (unlikely(tsk->flags & PF_EXITING)) { 
   		printk(KERN_ALERT
   			"Fixing recursive fault but reboot is needed!\n");
   		/* //这段注释说明在这里可以不加锁进行操作。Futex（快速用户空间互斥量）代码使用这个标志来验证优先级继承状态的清理是否完成。在最坏的情况下，它可能会再循环一次。由于没有返回的方式，所以假装清理已经完成。此时要么设置了 OWNER_DIED 标志，要么将阻塞的任务推入等待状态。
   		 * We can do this unlocked here. The futex code uses
   		 * this flag just to verify whether the pi state
   		 * cleanup has been done or not. In the worst case it
   		 * loops once more. We pretend that the cleanup was
   		 * done as there is no way to return. Either the
   		 * OWNER_DIED bit is set by now or we push the blocked
   		 * task into the wait for ever nirwana as well.
   		 */
   		tsk->flags |= PF_EXITPIDONE;
   		set_current_state(TASK_UNINTERRUPTIBLE); //设置任务不可被中断
   		schedule();	//调用 schedule(); 进行任务调度。此时，当前任务将被挂起，等待其他任务的调度。
   	}

   	exit_irq_thread(); //调用 exit_irq_thread() 函数，通常用于清理与中断相关的资源。这意味着当前线程可能是一个中断处理线程，执行此操作以安全地退出该线程。

   	exit_signals(tsk);  /* sets PF_EXITING */ //调用 exit_signals(tsk); 函数，处理与任务 tsk 相关的退出信号。这会设置任务的 PF_EXITING 标志，表示该任务正在退出状态
   	/*
   	 * tsk->flags are checked in the futex code to protect against
   	 * an exiting task cleaning up the robust pi futexes.
   	 */
   	smp_mb(); //函数用于插入一个全局内存屏障，确保在此之前的所有内存操作都已经完成。这是为了防止编译器或 CPU 重排指令，从而保证在多核系统中，内存操作的可见性和一致性。
   	raw_spin_unlock_wait(&tsk->pi_lock); //用于解锁任务的优先级继承锁 pi_lock。在某些情况下，可能需要等待锁被完全解锁，以确保后续操作的安全性。

   	if (unlikely(in_atomic()))
   		printk(KERN_INFO "note: %s[%d] exited with preempt_count %d\n",
   				current->comm, task_pid_nr(current),
   				preempt_count());

   	acct_update_integrals(tsk); //调用 acct_update_integrals(tsk); 函数更新与任务 tsk 相关的会计信息。这通常涉及到资源使用的统计，例如CPU时间、内存使用等。
   	/* sync mm's RSS info before statistics gathering */
   	if (tsk->mm)
   		sync_mm_rss(tsk, tsk->mm); //注释说明在收集统计信息之前，需要同步任务的内存使用信息（RSS）。如果任务有内存管理结构（tsk->mm），则调用 sync_mm_rss(tsk, tsk->mm); 来同步相关的内存信息。
   	group_dead = atomic_dec_and_test(&tsk->signal->live); //使用 atomic_dec_and_test(&tsk->signal->live); 函数减少当前任务组的活跃任务计数，并检查任务组是否已死亡。如果返回值为真，表示该任务组已经没有活跃任务。
   	if (group_dead) {
   		hrtimer_cancel(&tsk->signal->real_timer); //首先取消与任务相关的实时定时器
   		exit_itimers(tsk->signal); //函数退出与该任务信号相关的定时器。
   		if (tsk->mm)
   			setmax_mm_hiwater_rss(&tsk->signal->maxrss, tsk->mm); //更新任务组的最大RSS（常驻集大小）记录。
   	}
   	acct_collect(code, group_dead); //调用 acct_collect(code, group_dead); 函数收集与任务退出相关的会计信息。这里的 code 是退出状态，group_dead 表示任务组是否已经死亡。
   	if (group_dead)
   		tty_audit_exit(); //调用 tty_audit_exit(); 进行TTY（终端）审计退出的处理，确保审计相关的资源得到清理。
   	if (unlikely(tsk->audit_context))
   		audit_free(tsk); //函数释放与任务相关的审计资源。

   	tsk->exit_code = code;
   	taskstats_exit(tsk, group_dead); //调用 taskstats_exit(tsk, group_dead); 函数更新与任务 tsk 相关的统计信息，group_dead 指示任务组是否已经死亡。

   	exit_mm(tsk); //调用 exit_mm(tsk); 函数，清理与任务相关的内存管理信息。这包括释放该任务占用的内存资源。

   	if (group_dead)
   		acct_process(); //如果任务组已经死亡，调用 acct_process(); 函数收集和记录进程的会计信息。
   	trace_sched_process_exit(tsk); //调用 trace_sched_process_exit(tsk); 函数，记录任务退出的调度信息，以便进行性能分析和调试。

   	exit_sem(tsk); //调用 exit_sem(tsk); 函数，清理与任务相关的信号量信息。这确保在任务退出时，信号量的状态能够正确更新。
   	exit_files(tsk); //调用 exit_files(tsk); 函数，清理与任务相关的打开文件描述符，释放文件资源。
   	exit_fs(tsk); //调用 exit_fs(tsk); 函数，清理与任务的文件系统上下文相关的信息。这通常涉及到更新当前工作目录和根目录等。
   	check_stack_usage(); //调用 check_stack_usage(); 函数，检查当前任务的栈使用情况。这是为了确保栈的使用在安全范围内。
   	exit_thread(); //调用 exit_thread(); 函数，进行线程的清理工作。这涉及到线程相关的资源释放和状态更新。
   	cgroup_exit(tsk, 1); //调用 cgroup_exit(tsk, 1); 函数，处理与任务相关的控制组（cgroup）信息的清理。这里的 1 可能表示退出时的一些标志或参数。

   	if (group_dead)
   		disassociate_ctty(1); //如果任务组已经死亡，调用 disassociate_ctty(1); 函数解除与控制终端的关联，确保不再有无效的终端连接。

   	module_put(task_thread_info(tsk)->exec_domain->module); //调用 module_put(...) 释放与任务执行域相关的模块引用。这是为了确保模块的正确管理和释放。

   	proc_exit_connector(tsk); //调用 proc_exit_connector(tsk); 函数，处理与任务退出相关的连接信息，确保与进程相关的接口得到正确处理。

   	/*
   	 * FIXME: do that only when needed, using sched_exit tracepoint
   	 */
   	flush_ptrace_hw_breakpoint(tsk); //调用 flush_ptrace_hw_breakpoint(tsk); 函数，清除与任务 tsk 相关的硬件断点。这通常用于确保调试器或跟踪工具不再监视该任务。
   	/*
   	 * Flush inherited counters to the parent - before the parent
   	 * gets woken up by child-exit notifications.
   	 */ //注释说明在父任务被子任务退出通知唤醒之前，刷新继承的计数器。
   	perf_event_exit_task(tsk); //调用 perf_event_exit_task(tsk); 函数，更新与任务的性能事件相关的信息，确保父任务能够获得准确的统计数据。

   	exit_notify(tsk, group_dead); //调用 exit_notify(tsk, group_dead); 函数，通知其他相关任务（如父任务）关于 tsk 任务退出的信息。
   #ifdef CONFIG_NUMA
   	mpol_put(tsk->mempolicy); //如果启用了NUMA（非统一内存访问）支持，调用 mpol_put(tsk->mempolicy); 释放与任务相关的内存策略，并将其指针设为 NULL。
   	tsk->mempolicy = NULL;
   #endif
   #ifdef CONFIG_FUTEX
   	if (unlikely(current->pi_state_cache))
   		kfree(current->pi_state_cache); //如果启用了Futex支持，检查当前任务的优先级继承状态缓存 pi_state_cache 是否存在，如果存在，则释放其内存。
   #endif
   	/*
   	 * Make sure we are holding no locks:
   	 */
   	debug_check_no_locks_held(tsk); //调用 debug_check_no_locks_held(tsk); 确保在退出时没有持有任何锁。这是为了防止死锁和资源竞争。
   	/*
   	 * We can do this unlocked here. The futex code uses this flag
   	 * just to verify whether the pi state cleanup has been done
   	 * or not. In the worst case it loops once more.
   	 */
   	tsk->flags |= PF_EXITPIDONE; //将 PF_EXITPIDONE 标志设置到任务的标志中，表示任务的退出处理已完成

   	if (tsk->io_context)
   		exit_io_context(tsk); //如果任务有I/O上下文，调用 exit_io_context(tsk); 函数，清理与任务相关的I/O上下文信息。

   	if (tsk->splice_pipe)
   		__free_pipe_info(tsk->splice_pipe); //如果任务有用于分隔的管道，调用 __free_pipe_info(tsk->splice_pipe); 函数释放与之相关的管道信息。

   	validate_creds_for_do_exit(tsk); //调用 validate_creds_for_do_exit(tsk); 函数，验证任务在退出时是否具备合适的凭据和权限。

   	preempt_disable(); //调用 preempt_disable(); 禁用抢占，以确保在任务退出期间不会被其他任务打断。
   	exit_rcu(); //调用 exit_rcu(); 进行RCU（读-复制-更新）相关的清理工作，确保RCU机制的正常工作。
   	/* causes final put_task_struct in finish_task_switch(). */
   	tsk->state = TASK_DEAD; //将任务的状态设置为 TASK_DEAD，表示该任务已经死亡。
   	schedule(); //然后调用 schedule(); 进行任务调度，准备切换到其他任务。
   	BUG(); 
   	/* Avoid "noreturn function does return".  */
   	for (;;) //调用 BUG(); 触发一个严重错误，导致内核崩溃。接下来的循环 for (;;) 是为了避免编译器警告，表示当 BUG 函数为空时依然会进入此循环，保持CPU空闲
   		cpu_relax();	/* For when BUG is null */ //
   }
   ```
