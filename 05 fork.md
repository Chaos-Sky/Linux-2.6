# fork内核实现do_fork

```c
/*
 *  Ok, this is the main fork-routine.
 *
 * It copies the process, and if successful kick-starts
 * it and waits for it to finish using the VM if required.
 */
long do_fork(unsigned long clone_flags,
	      unsigned long stack_start,
	      struct pt_regs *regs,
	      unsigned long stack_size,
	      int __user *parent_tidptr,
	      int __user *child_tidptr)
{
	struct task_struct *p;
	int trace = 0;
	long nr;

	/*
	 * Do some preliminary argument and permissions checking before we
	 * actually start allocating stuff
	 */
	if (clone_flags & CLONE_NEWUSER) {
		if (clone_flags & CLONE_THREAD)
			return -EINVAL;
		/* hopefully this check will go away when userns support is
		 * complete
		 */
		if (!capable(CAP_SYS_ADMIN) || !capable(CAP_SETUID) ||
				!capable(CAP_SETGID))
			return -EPERM;
	}

	/*
	 * We hope to recycle these flags after 2.6.26
	 */
	if (unlikely(clone_flags & CLONE_STOPPED)) {
		static int __read_mostly count = 100;

		if (count > 0 && printk_ratelimit()) {
			char comm[TASK_COMM_LEN];

			count--;
			printk(KERN_INFO "fork(): process `%s' used deprecated "
					"clone flags 0x%lx\n",
				get_task_comm(comm, current),
				clone_flags & CLONE_STOPPED);
		}
	}

	/*
	 * When called from kernel_thread, don't do user tracing stuff.
	 */
	if (likely(user_mode(regs)))
		trace = tracehook_prepare_clone(clone_flags);

	p = copy_process(clone_flags, stack_start, regs, stack_size,
			 child_tidptr, NULL, trace);
	/*
	 * Do this prior waking up the new thread - the thread pointer
	 * might get invalid after that point, if the thread exits quickly.
	 */
	if (!IS_ERR(p)) {
		struct completion vfork;

		trace_sched_process_fork(current, p);				// trace_sched_process_fork 函数的主要作用是记录和跟踪进程的创建事件，提供有关系统进程管理的实时信息。这对于性能分析、调试和系统监控都是非常有价值的。

		nr = task_pid_vnr(p); 								// 返回的 nr 通常就是进程的 PID

		if (clone_flags & CLONE_PARENT_SETTID)
			put_user(nr, parent_tidptr);

		if (clone_flags & CLONE_VFORK) {
			p->vfork_done = &vfork;
			init_completion(&vfork);
		}

		audit_finish_fork(p); 								// audit_finish_fork 函数的主要作用是完成对新创建进程的审计记录，提供有关安全事件的详细信息。
		tracehook_report_clone(regs, clone_flags, nr, p); 	// tracehook_report_clone 函数的主要作用是记录和跟踪进程克隆事件，提供有关进程创建的详细信息

		/*
		 * We set PF_STARTING at creation in case tracing wants to
		 * use this to distinguish a fully live task from one that
		 * hasn't gotten to tracehook_report_clone() yet.  Now we
		 * clear it and set the child going.
		 */
		p->flags &= ~PF_STARTING;

		if (unlikely(clone_flags & CLONE_STOPPED)) {
			/*
			 * We'll start up with an immediate SIGSTOP.
			 */
			sigaddset(&p->pending.signal, SIGSTOP);
			set_tsk_thread_flag(p, TIF_SIGPENDING);
			__set_task_state(p, TASK_STOPPED);
		} else {
			wake_up_new_task(p, clone_flags); // wake_up_new_task 函数的主要作用是将新创建的任务标记为可调度，允许其开始执行。
		}

		tracehook_report_clone_complete(trace, regs,
						clone_flags, nr, p); //标志完成

		if (clone_flags & CLONE_VFORK) {
			freezer_do_not_count();
			wait_for_completion(&vfork);
			freezer_count();
			tracehook_report_vfork_done(p, nr);
		}
	} else {
		nr = PTR_ERR(p);
	}
	return nr;
}
```

    do_fork两个核心函数copy_process和wake_up_new_task，
    copy_process负责拷贝当前的进程信息
    wake_up_new_task将新的task_struct放入到调度链表中，并激活进程

## copy_process 进程拷贝
```c
/*
 * This creates a new process as a copy of the old one,
 * but does not actually start it yet.
 *
 * It copies the registers, and all the appropriate
 * parts of the process environment (as per the clone
 * flags). The actual kick-off is left to the caller.
 */
static struct task_struct *copy_process(unsigned long clone_flags,
					unsigned long stack_start,
					struct pt_regs *regs,
					unsigned long stack_size,
					int __user *child_tidptr,
					struct pid *pid,
					int trace)
{
	int retval;
	struct task_struct *p;
	int cgroup_callbacks_done = 0;

	if ((clone_flags & (CLONE_NEWNS|CLONE_FS)) == (CLONE_NEWNS|CLONE_FS))
		return ERR_PTR(-EINVAL);

	/*
	 * Thread groups must share signals as well, and detached threads
	 * can only be started up within the thread group.
	 */
	if ((clone_flags & CLONE_THREAD) && !(clone_flags & CLONE_SIGHAND))
		return ERR_PTR(-EINVAL);

	/*
	 * Shared signal handlers imply shared VM. By way of the above,
	 * thread groups also imply shared VM. Blocking this case allows
	 * for various simplifications in other code.
	 */
	if ((clone_flags & CLONE_SIGHAND) && !(clone_flags & CLONE_VM))
		return ERR_PTR(-EINVAL);

	/*
	 * Siblings of global init remain as zombies on exit since they are
	 * not reaped by their parent (swapper). To solve this and to avoid
	 * multi-rooted process trees, prevent global and container-inits
	 * from creating siblings.
	 */
	if ((clone_flags & CLONE_PARENT) &&
				current->signal->flags & SIGNAL_UNKILLABLE)
		return ERR_PTR(-EINVAL);

	retval = security_task_create(clone_flags); //Linux 内核中用于在创建新进程时执行安全检查的函数。这个函数通常被调用以确保新进程的创建符合安全策略。
	if (retval)
		goto fork_out;

	retval = -ENOMEM;
	p = dup_task_struct(current); // 使用 dup_task_struct 复制当前进程的任务结构。
	if (!p)
		goto fork_out;

	ftrace_graph_init_task(p); //fstrace相关

	rt_mutex_init_task(p); //Linux 内核中用于初始化实时互斥锁（RT mutex）的函数。这一函数在新进程或线程创建时被调用，以确保进程能够正确使用实时互斥锁。

#ifdef CONFIG_PROVE_LOCKING
	DEBUG_LOCKS_WARN_ON(!p->hardirqs_enabled);
	DEBUG_LOCKS_WARN_ON(!p->softirqs_enabled);
#endif
	retval = -EAGAIN;
	if (atomic_read(&p->real_cred->user->processes) >=
			task_rlimit(p, RLIMIT_NPROC)) { // 进程限制检查
		if (!capable(CAP_SYS_ADMIN) && !capable(CAP_SYS_RESOURCE) &&
		    p->real_cred->user != INIT_USER)
			goto bad_fork_free;
	}

	retval = copy_creds(p, clone_flags); //复制 fork（） 创建的新进程的凭据，如果可以的话，我们会分享，但在某些情况下，我们必须生成一个 newset
	if (retval < 0)
		goto bad_fork_free;

	/*
	 * If multiple threads are within copy_process(), then this check
	 * triggers too late. This doesn't hurt, the check is only there
	 * to stop root fork bombs.
	 */
	retval = -EAGAIN;
	if (nr_threads >= max_threads)
		goto bad_fork_cleanup_count;

	if (!try_module_get(task_thread_info(p)->exec_domain->module))
		goto bad_fork_cleanup_count;

	p->did_exec = 0;
	delayacct_tsk_init(p);	/* Must remain after dup_task_struct() */
	copy_flags(clone_flags, p); //赋值标志物，比如PF_THREAD
	INIT_LIST_HEAD(&p->children); //初始化自生子进程链表
	INIT_LIST_HEAD(&p->sibling);	//初始化自生子进程的兄弟链表
	rcu_copy_process(p);
	p->vfork_done = NULL;
	spin_lock_init(&p->alloc_lock); // 初始化自旋锁

	init_sigpending(&p->pending); // 是 Linux 内核中用于初始化进程的信号待处理列表的函数。该函数确保进程的信号状态在创建时处于一致的初始状态。将进程的 pending 信号状态设置为一个干净的状态，确保没有待处理的信号。

	p->utime = cputime_zero;
	p->stime = cputime_zero;
	p->gtime = cputime_zero;
	p->utimescaled = cputime_zero;
	p->stimescaled = cputime_zero;
#ifndef CONFIG_VIRT_CPU_ACCOUNTING
	p->prev_utime = cputime_zero;
	p->prev_stime = cputime_zero;
#endif
#if defined(SPLIT_RSS_COUNTING)
	memset(&p->rss_stat, 0, sizeof(p->rss_stat));
#endif

	p->default_timer_slack_ns = current->timer_slack_ns;

	task_io_accounting_init(&p->ioac); // Linux 内核中用于初始化进程的 I/O 账户信息的函数。该函数确保进程的 I/O 统计信息在创建时处于一致的初始状态。
	acct_clear_integrals(p); // Linux 内核中用于清除进程的资源使用统计信息的函数。具体来说，它用于重置进程的资源使用计数，以便在新进程创建时，确保进程的资源使用数据是干净的。

	posix_cpu_timers_init(p); // Linux 内核中用于初始化进程的 POSIX CPU 定时器的函数。它确保新创建的进程的 CPU 定时器状态处于一致的初始状态。

	p->lock_depth = -1;		/* -1 = no lock */
	do_posix_clock_monotonic_gettime(&p->start_time); // Linux 内核中用于获取当前单调时钟时间并将其存储在进程结构中的函数。这通常在进程创建时被调用，以记录进程的启动时间。
	p->real_start_time = p->start_time;
	monotonic_to_bootbased(&p->real_start_time); //Linux 内核中用于将单调时钟时间转换为基于启动时间的时间格式的函数。这通常在进程创建时调用，以便记录进程启动时的实际时间。
	p->io_context = NULL;
	p->audit_context = NULL;
	cgroup_fork(p); //Linux 内核中用于处理进程创建时的控制组（cgroup）相关操作的函数。这个函数在新进程的上下文中被调用，以确保新进程适当地关联到其控制组。
#ifdef CONFIG_NUMA
	p->mempolicy = mpol_dup(p->mempolicy);
 	if (IS_ERR(p->mempolicy)) {
 		retval = PTR_ERR(p->mempolicy);
 		p->mempolicy = NULL;
 		goto bad_fork_cleanup_cgroup;
 	}
	mpol_fix_fork_child_flag(p);
#endif
#ifdef CONFIG_TRACE_IRQFLAGS
	p->irq_events = 0;
#ifdef __ARCH_WANT_INTERRUPTS_ON_CTXSW
	p->hardirqs_enabled = 1;
#else
	p->hardirqs_enabled = 0;
#endif
	p->hardirq_enable_ip = 0;
	p->hardirq_enable_event = 0;
	p->hardirq_disable_ip = _THIS_IP_;
	p->hardirq_disable_event = 0;
	p->softirqs_enabled = 1;
	p->softirq_enable_ip = _THIS_IP_;
	p->softirq_enable_event = 0;
	p->softirq_disable_ip = 0;
	p->softirq_disable_event = 0;
	p->hardirq_context = 0;
	p->softirq_context = 0;
#endif
#ifdef CONFIG_LOCKDEP
	p->lockdep_depth = 0; /* no locks held yet */
	p->curr_chain_key = 0;
	p->lockdep_recursion = 0;
#endif

#ifdef CONFIG_DEBUG_MUTEXES
	p->blocked_on = NULL; /* not blocked yet */
#endif
#ifdef CONFIG_CGROUP_MEM_RES_CTLR
	p->memcg_batch.do_batch = 0;
	p->memcg_batch.memcg = NULL;
#endif

	p->bts = NULL;

	/* Perform scheduler related setup. Assign this task to a CPU. */
	sched_fork(p, clone_flags); //Linux 内核中在进程创建过程中用于调度相关初始化的函数。它在新进程创建时被调用，以确保调度器能够正确管理新进程。
 
	retval = perf_event_init_task(p); //Linux 内核中用于初始化新进程性能事件的函数。这一函数在进程创建过程中被调用，以便设置与性能监测相关的参数。
	if (retval)
		goto bad_fork_cleanup_policy;

	if ((retval = audit_alloc(p)))
		goto bad_fork_cleanup_policy;
	/* copy all the process information */
	if ((retval = copy_semundo(clone_flags, p)))
		goto bad_fork_cleanup_audit;
	if ((retval = copy_files(clone_flags, p)))
		goto bad_fork_cleanup_semundo;
	if ((retval = copy_fs(clone_flags, p)))
		goto bad_fork_cleanup_files;
	if ((retval = copy_sighand(clone_flags, p)))
		goto bad_fork_cleanup_fs;
	if ((retval = copy_signal(clone_flags, p)))
		goto bad_fork_cleanup_sighand;
	if ((retval = copy_mm(clone_flags, p)))
		goto bad_fork_cleanup_signal;
	if ((retval = copy_namespaces(clone_flags, p)))
		goto bad_fork_cleanup_mm;
	if ((retval = copy_io(clone_flags, p)))
		goto bad_fork_cleanup_namespaces;
	retval = copy_thread(clone_flags, stack_start, stack_size, p, regs);
	if (retval)
		goto bad_fork_cleanup_io;

	if (pid != &init_struct_pid) {
		retval = -ENOMEM;
		pid = alloc_pid(p->nsproxy->pid_ns); //分配一下struct pid *结构体
		if (!pid)
			goto bad_fork_cleanup_io;

		if (clone_flags & CLONE_NEWPID) {
			retval = pid_ns_prepare_proc(p->nsproxy->pid_ns);
			if (retval < 0)
				goto bad_fork_free_pid;
		}
	}

	p->pid = pid_nr(pid); //赋值pid
	p->tgid = p->pid;		//线程组pid
	if (clone_flags & CLONE_THREAD)
		p->tgid = current->tgid;

	if (current->nsproxy != p->nsproxy) {
		retval = ns_cgroup_clone(p, pid);//Linux 内核中用于处理新进程与命名空间和控制组（cgroup）关系的函数。这一函数在进程创建时被调用，以确保新进程在适当的命名空间和控制组中运行。
		if (retval)
			goto bad_fork_free_pid;
	}

	p->set_child_tid = (clone_flags & CLONE_CHILD_SETTID) ? child_tidptr : NULL;
	/*
	 * Clear TID on mm_release()?
	 */
	p->clear_child_tid = (clone_flags & CLONE_CHILD_CLEARTID) ? child_tidptr: NULL;
#ifdef CONFIG_FUTEX
	p->robust_list = NULL;
#ifdef CONFIG_COMPAT
	p->compat_robust_list = NULL;
#endif
	INIT_LIST_HEAD(&p->pi_state_list);
	p->pi_state_cache = NULL;
#endif
	/*
	 * sigaltstack should be cleared when sharing the same VM
	 */
	if ((clone_flags & (CLONE_VM|CLONE_VFORK)) == CLONE_VM)
		p->sas_ss_sp = p->sas_ss_size = 0;

	/*
	 * Syscall tracing and stepping should be turned off in the
	 * child regardless of CLONE_PTRACE.
	 */
	user_disable_single_step(p); //是 Linux 内核中用于在新进程上下文中禁用单步调试功能的函数。这通常在进程创建时调用，以确保进程在运行时不会被单步调试打断。
	clear_tsk_thread_flag(p, TIF_SYSCALL_TRACE);//Linux 内核中用于清除进程线程标志的函数，特别是与系统调用跟踪相关的标志。这通常在进程创建时调用，以确保新进程的状态是干净的，不受父进程的调试状态影响。
#ifdef TIF_SYSCALL_EMU
	clear_tsk_thread_flag(p, TIF_SYSCALL_EMU);
#endif
	clear_all_latency_tracing(p);//Linux 内核中用于清除与延迟跟踪相关的信息的函数。这一函数通常在进程创建时调用，以确保新进程的延迟跟踪状态是干净的。

	/* ok, now we should be set up.. */
	p->exit_signal = (clone_flags & CLONE_THREAD) ? -1 : (clone_flags & CSIGNAL);
	p->pdeath_signal = 0;
	p->exit_state = 0;

	/*
	 * Ok, make it visible to the rest of the system.
	 * We dont wake it up yet.
	 */
	p->group_leader = p;	
	INIT_LIST_HEAD(&p->thread_group); //初始化线程组

	/* Now that the task is set up, run cgroup callbacks if
	 * necessary. We need to run them before the task is visible
	 * on the tasklist. */
	cgroup_fork_callbacks(p); // Linux 内核中用于在新进程创建时执行控制组（cgroup）相关回调的函数。该函数在进程创建过程中被调用，以确保与控制组相关的任何必要的初始化或更新操作被执行。
	cgroup_callbacks_done = 1;

	/* Need tasklist lock for parent etc handling! */
	write_lock_irq(&tasklist_lock);

	/* CLONE_PARENT re-uses the old parent */
	if (clone_flags & (CLONE_PARENT|CLONE_THREAD)) {
		p->real_parent = current->real_parent;
		p->parent_exec_id = current->parent_exec_id;
	} else {
		p->real_parent = current;
		p->parent_exec_id = current->self_exec_id;
	}

	spin_lock(&current->sighand->siglock);

	/*
	 * Process group and session signals need to be delivered to just the
	 * parent before the fork or both the parent and the child after the
	 * fork. Restart if a signal comes in before we add the new process to
	 * it's process group.
	 * A fatal signal pending means that current will exit, so the new
	 * thread can't slip out of an OOM kill (or normal SIGKILL).
 	 */
	recalc_sigpending(); //确保进程的待处理信号状态是最新的，从而支持有效的信号管理和处理
	if (signal_pending(current)) {
		spin_unlock(&current->sighand->siglock);
		write_unlock_irq(&tasklist_lock);
		retval = -ERESTARTNOINTR;
		goto bad_fork_free_pid;
	}

	if (clone_flags & CLONE_THREAD) {
		atomic_inc(&current->signal->count);
		atomic_inc(&current->signal->live);
		p->group_leader = current->group_leader;
		list_add_tail_rcu(&p->thread_group, &p->group_leader->thread_group);
	}

	if (likely(p->pid)) {
		tracehook_finish_clone(p, clone_flags, trace);

		if (thread_group_leader(p)) { //该条件检查新进程 p 是否是其线程组的领导者。线程组领导者通常是该组中第一个创建的线程。
			if (clone_flags & CLONE_NEWPID) //如果使用了 CLONE_NEWPID 标志，表示新进程将拥有新的 PID 命名空间，此时设置这个命名空间的子收割者（child reaper）为新进程 p。子收割者负责收集其子进程的退出状态。
				p->nsproxy->pid_ns->child_reaper = p;

			p->signal->leader_pid = pid; //将新进程的领导者 PID 设置为当前进程的 PID。
			tty_kref_put(p->signal->tty); //释放当前进程信号结构中与终端（TTY）相关的引用，并将新进程的终端设置为继承自当前进程的终端。
			p->signal->tty = tty_kref_get(current->signal->tty);
			attach_pid(p, PIDTYPE_PGID, task_pgrp(current)); //将新进程 p 附加到当前进程所在的进程组 ID（PGID）和会话 ID（SID）。这有助于在进程管理中维护进程之间的关系和组织结构
			attach_pid(p, PIDTYPE_SID, task_session(current));
			list_add_tail(&p->sibling, &p->real_parent->children); //将新进程添加到其父进程的子进程列表中，确保内核能够跟踪其父子关系。
			list_add_tail_rcu(&p->tasks, &init_task.tasks); //将新进程添加到全局任务列表中，这样内核可以调度它。使用 RCU（Read-Copy-Update）机制确保在并发环境中的安全性。
			__get_cpu_var(process_counts)++; //__get_cpu_var(process_counts)++;
		}
		attach_pid(p, PIDTYPE_PID, pid);
		nr_threads++; //nr_threads 是一个全局变量，用于跟踪当前系统中活跃线程的数量
	}

	total_forks++; //total_forks 是一个全局变量，用于跟踪系统中创建的进程总数
	spin_unlock(&current->sighand->siglock);
	write_unlock_irq(&tasklist_lock);
	proc_fork_connector(p); //调用 proc_fork_connector 函数，处理与进程相关的用户空间通知。这通常涉及到向用户空间的某些监听器发送关于新进程创建的事件。
	cgroup_post_fork(p); //调用 cgroup_post_fork，执行与控制组相关的后处理。这确保新进程能够正确地关联到其控制组，并遵循相关的资源限制和监控。
	perf_event_fork(p);//调用 perf_event_fork，初始化新进程的性能事件监控。这为后续的性能分析和监控做好准备。
	return p;

bad_fork_free_pid:
	if (pid != &init_struct_pid)
		free_pid(pid);
bad_fork_cleanup_io:
	if (p->io_context)
		exit_io_context(p);
bad_fork_cleanup_namespaces:
	exit_task_namespaces(p);
bad_fork_cleanup_mm:
	if (p->mm)
		mmput(p->mm);
bad_fork_cleanup_signal:
	if (!(clone_flags & CLONE_THREAD))
		__cleanup_signal(p->signal);
bad_fork_cleanup_sighand:
	__cleanup_sighand(p->sighand);
bad_fork_cleanup_fs:
	exit_fs(p); /* blocking */
bad_fork_cleanup_files:
	exit_files(p); /* blocking */
bad_fork_cleanup_semundo:
	exit_sem(p);
bad_fork_cleanup_audit:
	audit_free(p);
bad_fork_cleanup_policy:
	perf_event_free_task(p);
#ifdef CONFIG_NUMA
	mpol_put(p->mempolicy);
bad_fork_cleanup_cgroup:
#endif
	cgroup_exit(p, cgroup_callbacks_done);
	delayacct_tsk_free(p);
	module_put(task_thread_info(p)->exec_domain->module);
bad_fork_cleanup_count:
	atomic_dec(&p->cred->user->processes);
	exit_creds(p);
bad_fork_free:
	free_task(p);
fork_out:
	return ERR_PTR(retval);
}

```

## 唤醒进程
```c
/*
 * wake_up_new_task - wake up a newly created task for the first time.
 *
 * This function will do some initial scheduler statistics housekeeping
 * that must be done for every newly created context, then puts the task
 * on the runqueue and wakes it.
 */
void wake_up_new_task(struct task_struct *p, unsigned long clone_flags)
{
	unsigned long flags;
	struct rq *rq;
	int cpu __maybe_unused = get_cpu();

#ifdef CONFIG_SMP
	/*
	 * Fork balancing, do it here and not earlier because:
	 *  - cpus_allowed can change in the fork path
	 *  - any previously selected cpu might disappear through hotplug
	 *
	 * We still have TASK_WAKING but PF_STARTING is gone now, meaning
	 * ->cpus_allowed is stable, we have preemption disabled, meaning
	 * cpu_online_mask is stable.
	 */
	cpu = select_task_rq(p, SD_BALANCE_FORK, 0);
	set_task_cpu(p, cpu);
#endif

	/*
	 * Since the task is not on the rq and we still have TASK_WAKING set
	 * nobody else will migrate this task.
	 */
	rq = cpu_rq(cpu);
	raw_spin_lock_irqsave(&rq->lock, flags);

	BUG_ON(p->state != TASK_WAKING);
	p->state = TASK_RUNNING;
	update_rq_clock(rq);
	activate_task(rq, p, 0); 			//将进程 p 激活到运行队列中，准备调度。
	trace_sched_wakeup_new(rq, p, 1);
	check_preempt_curr(rq, p, WF_FORK); //检查当前任务是否需要被抢占。如果是的话，调度器将决定是否切换到新唤醒的任务。
#ifdef CONFIG_SMP
	if (p->sched_class->task_woken)
		p->sched_class->task_woken(rq, p);
#endif
	task_rq_unlock(rq, &flags);
	put_cpu();
}
```

```c
/*
 * activate_task - move a task to the runqueue.
 */
static void activate_task(struct rq *rq, struct task_struct *p, int wakeup)
{
	if (task_contributes_to_load(p)) //这段代码检查任务 p 是否对负载有贡献。task_contributes_to_load 是一个函数，如果返回真，则表明该任务在 nr_uninterruptible 中计数。此时将 nr_uninterruptible 递减，表明当前不可中断任务的数量减少。
		rq->nr_uninterruptible--;

	enqueue_task(rq, p, wakeup, false); //调用 enqueue_task 函数将任务 p 添加到运行队列 rq 中。wakeup 参数用于指示任务是否是由于唤醒操作而加入队列，false 则表示没有额外的标志。
	inc_nr_running(rq); //可运行任务 + 1
}
```

```c
static void enqueue_task(struct rq *rq, struct task_struct *p, int wakeup, bool head)
{
	if (wakeup)
		p->se.start_runtime = p->se.sum_exec_runtime; //如果 wakeup 为真，表示任务是因为唤醒而被加入队列，此时将任务的 start_runtime 设置为其 sum_exec_runtime。这确保了任务在被调度时可以正确计算运行时间。

	sched_info_queued(p); // 调用 sched_info_queued 函数记录任务 p 被入队的信息。这通常用于调度统计和性能分析。
	p->sched_class->enqueue_task(rq, p, wakeup, head); //关键点
	p->se.on_rq = 1; //记录当前在运行调度链中
}
```

```c
/*
 * The enqueue_task method is called before nr_running is
 * increased. Here we update the fair scheduling stats and
 * then put the task into the rbtree:
 */
static void enqueue_task_fair(struct rq *rq, struct task_struct *p, int wakeup, bool head)
{
	struct cfs_rq *cfs_rq;
	struct sched_entity *se = &p->se;
	int flags = 0;

	if (wakeup) //如果是要被唤醒状态
		flags |= ENQUEUE_WAKEUP;
	if (p->state == TASK_WAKING)
		flags |= ENQUEUE_MIGRATE;

	for_each_sched_entity(se) {
		if (se->on_rq) // 如果它已经在运行队列中，则跳出循环
			break;
		cfs_rq = cfs_rq_of(se); //获取对应的公平调度运行队列 cfs_rq
		enqueue_entity(cfs_rq, se, flags); //调用 enqueue_entity 函数将当前调度实体加入到运行队列中，并传递相应的标志。
		flags = ENQUEUE_WAKEUP; //将 flags 设置为 ENQUEUE_WAKEUP，以确保后续的调度实体都标记为唤醒状态。
	}

	hrtick_update(rq); //调用 hrtick_update 函数更新高分辨率定时器，这是为了确保调度器可以准确地管理定时任务。
}
```

```c
static inline struct cfs_rq *cfs_rq_of(struct sched_entity *se)
{
	struct task_struct *p = task_of(se); // 使用 task_of 宏或函数将调度实体 se 转换为相应的任务结构体指针 p。task_struct 是表示进程或线程的核心数据结构。
	struct rq *rq = task_rq(p); //使用 task_rq 函数获取与任务 p 相关联的运行队列（rq）。每个 CPU 核心都有一个运行队列，用于调度其上的任务。

	return &rq->cfs; //返回运行队列中的 CFS 运行队列部分的指针。rq->cfs 是一个结构，包含了与完全公平调度相关的所有信息。
}
```

```c

static void enqueue_entity(struct cfs_rq *cfs_rq, struct sched_entity *se, int flags)
{
	/* 在通过 callig update_curr（） 更新 min_vruntime 之前，更新规范化的 vruntime。
	 * Update the normalized vruntime before updating min_vruntime
	 * through callig update_curr().
	 */
	if (!(flags & ENQUEUE_WAKEUP) || (flags & ENQUEUE_MIGRATE))
		se->vruntime += cfs_rq->min_vruntime;

	/* 更新 'current' 的运行时统计信息。
	 * Update run-time statistics of the 'current'.
	 */
	update_curr(cfs_rq); 				// 该函数更新运行队列 cfs_rq 中当前任务的调度信息，通常包括运行时间和其他相关统计数据。
	account_entity_enqueue(cfs_rq, se); // 此函数用于更新调度实体 se 的入队统计信息。这可能涉及更新任务的调度时间、等待时间等。

	if (flags & ENQUEUE_WAKEUP) { 		// 如果 flags 中包含 ENQUEUE_WAKEUP，表示该任务是由于唤醒而被加入队列。指被阻塞的进程，即将被唤醒
		place_entity(cfs_rq, se, 0); 	// place_entity(cfs_rq, se, 0) 将任务 se 放置在适当的位置，通常是根据其优先级。
		enqueue_sleeper(cfs_rq, se); 	// enqueue_sleeper(cfs_rq, se) 将处于睡眠状态的任务加入到运行队列中。
	}

	update_stats_enqueue(cfs_rq, se); 	//更新与 se 相关的调度统计信息，以便准确反映调度状态。
	check_spread(cfs_rq, se); 			//该函数用于检查任务在 CPU 核心之间的负载均衡情况，确保调度器能够有效地分配任务。
	if (se != cfs_rq->curr)
		__enqueue_entity(cfs_rq, se); 	//如果 se 不是当前正在运行的调度实体（cfs_rq->curr），则调用 __enqueue_entity(cfs_rq, se) 将 se 实际加入到运行队列中。这通常涉及将任务添加到红黑树或其他数据结构中。
}
```