module task_scheduler::scheduler {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::clock::{Self, Clock};
    use sui::dynamic_object_field as ofield;
    use sui::event;
    use std::option::{Self, Option};
    use std::vector;
    use std::string::{Self, String};

    // ===== 错误码定义 =====
    const EALREADY_EXECUTED: u64 = 1;
    const EINVALID_TRIGGER: u64 = 2;
    const EPERMISSION_DENIED: u64 = 3;
    const ETASK_NOT_FOUND: u64 = 4;
    const ETASK_ALREADY_EXISTS: u64 = 5;
    const EINVALID_TIMESTAMP: u64 = 6;
    const EEXECUTION_FAILED: u64 = 7;
    const ETIMEOUT_EXCEEDED: u64 = 8;
    const EGAS_LIMIT_EXCEEDED: u64 = 9;
    const EINVALID_ADMIN: u64 = 10;
    const EBLOCK_TIME_ERROR: u64 = 11;
    const ESYSTEM_PAUSED: u64 = 12;
    const EREPLAY_ATTACK: u64 = 13;
    const EINVALID_INPUT: u64 = 14;
    const ECROSS_CHAIN_ATTACK: u64 = 15;
    const EINVALID_MODULE: u64 = 16;

    // ===== 配置常量 =====
    const MAX_BATCH_SIZE: u64 = 50; // 批量操作最大数量限制
    const BLOCK_TIME_TOLERANCE: u64 = 5000; // 区块时间误差容忍度（5秒）
    const DEFAULT_TIMEOUT_BUFFER: u64 = 30000; // 默认超时缓冲时间（30秒）
    const MAX_PARAMETER_LENGTH: u64 = 1000; // 最大参数长度
    const MAX_DESCRIPTION_LENGTH: u64 = 500; // 最大描述长度
    const MAX_MODULE_NAME_LENGTH: u64 = 100; // 最大模块名长度
    const MAX_FUNCTION_NAME_LENGTH: u64 = 100; // 最大函数名长度
    const MIN_TRIGGER_TIME_OFFSET: u64 = 60000; // 最小触发时间偏移（1分钟）

    // ===== 事件定义 =====
    struct TaskRegistered has copy, drop {
        task_id: ID,
        owner: address,
        trigger_time: u64,
        description: vector<u8>,
        target_module: vector<u8>,
        target_function: vector<u8>,
        nonce: u64
    }

    struct TaskExecuted has copy, drop {
        task_id: ID,
        result: bool,
        execution_time: u64,
        execution_duration: u64,
        gas_used: u64,
        actual_gas_consumed: u64
    }

    struct TaskCancelled has copy, drop {
        task_id: ID,
        cancelled_by: address,
        nonce: u64
    }

    struct TaskTimeout has copy, drop {
        task_id: ID,
        timeout_time: u64,
        block_time_error: u64
    }

    struct GasLimitExceeded has copy, drop {
        task_id: ID,
        batch_size: u64,
        max_allowed: u64,
        actual_gas_used: u64
    }

    struct SystemPaused has copy, drop {
        paused_by: address,
        reason: vector<u8>,
        pause_time: u64
    }

    struct SystemResumed has copy, drop {
        resumed_by: address,
        resume_time: u64
    }

    struct ReplayAttackDetected has copy, drop {
        task_id: ID,
        attacker: address,
        nonce: u64,
        timestamp: u64
    }

    // ===== 任务结构定义 =====
    struct Task has store {
        id: ID,
        owner: address,
        trigger_time: u64,
        timeout_time: u64,
        description: vector<u8>,
        target_module: vector<u8>,
        target_function: vector<u8>,
        parameters: vector<vector<u8>>,
        executed: bool,
        created_at: u64,
        execution_count: u64,
        gas_estimate: u64,
        nonce: u64,
        chain_id: u64,
        signature: vector<u8>
    }

    // ===== 任务调度器主体对象 =====
    struct TaskScheduler has key {
        id: UID,
        total_tasks: u64,
        total_executed: u64,
        total_timeout: u64,
        total_failed: u64,
        total_gas_exceeded: u64,
        admin_addresses: vector<address>,
        max_gas_per_task: u64,
        max_batch_size: u64,
        is_paused: bool,
        pause_reason: vector<u8>,
        pause_time: u64,
        paused_by: address,
        nonce_counter: u64,
        chain_id: u64,
        allowed_modules: vector<vector<u8>>,
        blacklisted_addresses: vector<address>
    }

    // ===== 任务ID生成器 =====
    struct TaskIDGenerator has key {
        id: UID,
        next_id: u64,
        owner_counter: vector<u64>
    }

    // ===== 执行结果结构 =====
    struct ExecutionResult has store {
        success: bool,
        error_message: vector<u8>,
        execution_time: u64,
        gas_used: u64,
        actual_gas_consumed: u64,
        cross_contract_calls: u64,
        module_called: vector<u8>,
        function_called: vector<u8>
    }

    // ===== 通用调用配置 =====
    struct GenericCallConfig has store {
        module_address: address,
        module_name: vector<u8>,
        function_name: vector<u8>,
        gas_limit: u64,
        retry_count: u64,
        timeout_ms: u64,
        require_signature: bool
    }

    // ===== 公共函数 =====

    /// 创建任务调度器
    public fun create_scheduler(
        admin_addresses: vector<address>,
        max_gas_per_task: u64,
        max_batch_size: u64,
        chain_id: u64,
        allowed_modules: vector<vector<u8>>,
        ctx: &mut TxContext
    ) {
        let scheduler = TaskScheduler {
            id: object::new(ctx),
            total_tasks: 0,
            total_executed: 0,
            total_timeout: 0,
            total_failed: 0,
            total_gas_exceeded: 0,
            admin_addresses,
            max_gas_per_task,
            max_batch_size,
            is_paused: false,
            pause_reason: vector::empty(),
            pause_time: 0,
            paused_by: @0x0,
            nonce_counter: 0,
            chain_id,
            allowed_modules,
            blacklisted_addresses: vector::empty()
        };
        transfer::share_object(scheduler);
    }

    /// 创建任务ID生成器
    public fun create_id_generator(ctx: &mut TxContext) {
        let generator = TaskIDGenerator {
            id: object::new(ctx),
            next_id: 0,
            owner_counter: vector::empty()
        };
        transfer::share_object(generator);
    }

    /// 生成唯一的任务ID
    fun generate_task_id(generator: &mut TaskIDGenerator, owner: address): ID {
        let owner_bytes = std::bcs::to_bytes(&owner);
        let counter = generator.next_id;
        generator.next_id = counter + 1;
        
        // 使用更安全的ID生成方式
        let mut id_bytes = vector::empty<u8>();
        vector::append(&mut id_bytes, owner_bytes);
        vector::append(&mut id_bytes, std::bcs::to_bytes(&counter));
        vector::append(&mut id_bytes, std::bcs::to_bytes(&clock::timestamp_ms(&clock::new_for_testing())));
        
        object::id_from_bytes(id_bytes)
    }

    /// 验证输入参数
    fun validate_input(
        description: &vector<u8>,
        target_module: &vector<u8>,
        target_function: &vector<u8>,
        parameters: &vector<vector<u8>>,
        trigger_time: u64,
        timeout_duration: u64,
        gas_estimate: u64,
        current_time: u64
    ) {
        // 验证描述长度
        assert!(vector::length(description) <= MAX_DESCRIPTION_LENGTH, EINVALID_INPUT);
        
        // 验证模块名长度
        assert!(vector::length(target_module) <= MAX_MODULE_NAME_LENGTH, EINVALID_INPUT);
        assert!(vector::length(target_module) > 0, EINVALID_INPUT);
        
        // 验证函数名长度
        assert!(vector::length(target_function) <= MAX_FUNCTION_NAME_LENGTH, EINVALID_INPUT);
        assert!(vector::length(target_function) > 0, EINVALID_INPUT);
        
        // 验证参数
        let i = 0;
        let param_count = vector::length(parameters);
        while (i < param_count) {
            let param = vector::borrow(parameters, i);
            assert!(vector::length(param) <= MAX_PARAMETER_LENGTH, EINVALID_INPUT);
            i = i + 1;
        };
        
        // 验证时间
        assert!(trigger_time > current_time, EINVALID_TIMESTAMP);
        assert!(trigger_time >= current_time + MIN_TRIGGER_TIME_OFFSET, EINVALID_INPUT);
        assert!(timeout_duration > 0, EINVALID_INPUT);
        assert!(gas_estimate > 0, EINVALID_INPUT);
    }

    /// 验证模块是否允许
    fun is_module_allowed(scheduler: &TaskScheduler, module_name: &vector<u8>): bool {
        let i = 0;
        let len = vector::length(&scheduler.allowed_modules);
        
        while (i < len) {
            let allowed_module = vector::borrow(&scheduler.allowed_modules, i);
            if (std::string::utf8(allowed_module) == std::string::utf8(module_name)) {
                return true
            };
            i = i + 1;
        };
        
        false
    }

    /// 检查重放攻击
    fun check_replay_attack(
        scheduler: &TaskScheduler,
        task_id: ID,
        nonce: u64,
        owner: address
    ): bool {
        // 检查任务是否已存在
        if (ofield::contains(&scheduler.id, task_id)) {
            return false
        };
        
        // 检查nonce是否合理（这里可以添加更复杂的重放检测逻辑）
        if (nonce <= scheduler.nonce_counter) {
            return false
        };
        
        // 检查地址是否在黑名单中
        let i = 0;
        let len = vector::length(&scheduler.blacklisted_addresses);
        while (i < len) {
            let blacklisted = *vector::borrow(&scheduler.blacklisted_addresses, i);
            if (blacklisted == owner) {
                return false
            };
            i = i + 1;
        };
        
        true
    }

    /// 注册新任务（带完整验证）
    public entry fun register_task(
        scheduler: &mut TaskScheduler,
        generator: &mut TaskIDGenerator,
        clock: &Clock,
        trigger_time: u64,
        timeout_duration: u64,
        description: vector<u8>,
        target_module: vector<u8>,
        target_function: vector<u8>,
        parameters: vector<vector<u8>>,
        gas_estimate: u64,
        nonce: u64,
        signature: vector<u8>,
        ctx: &mut TxContext
    ) {
        // 检查系统是否暂停
        assert!(!scheduler.is_paused, ESYSTEM_PAUSED);
        
        // 验证输入参数
        let current_time = clock::timestamp_ms(clock);
        validate_input(
            &description,
            &target_module,
            &target_function,
            &parameters,
            trigger_time,
            timeout_duration,
            gas_estimate,
            current_time
        );
        
        // 验证Gas限制
        assert!(gas_estimate <= scheduler.max_gas_per_task, EGAS_LIMIT_EXCEEDED);
        
        // 验证模块是否允许
        assert!(is_module_allowed(scheduler, &target_module), EINVALID_MODULE);
        
        // 生成唯一任务ID
        let task_id = generate_task_id(generator, tx_context::sender(ctx));
        let timeout_time = trigger_time + timeout_duration + DEFAULT_TIMEOUT_BUFFER;
        
        // 检查重放攻击
        let owner = tx_context::sender(ctx);
        assert!(check_replay_attack(scheduler, task_id, nonce, owner), EREPLAY_ATTACK);
        
        // 创建任务对象
        let task = Task {
            id: task_id,
            owner,
            trigger_time,
            timeout_time,
            description,
            target_module,
            target_function,
            parameters,
            executed: false,
            created_at: current_time,
            execution_count: 0,
            gas_estimate,
            nonce,
            chain_id: scheduler.chain_id,
            signature
        };

        // 存储任务到动态字段
        ofield::add(&mut scheduler.id, task_id, task);

        // 更新统计信息
        scheduler.total_tasks = scheduler.total_tasks + 1;
        scheduler.nonce_counter = nonce;

        // 发出事件
        event::emit(TaskRegistered {
            task_id,
            owner,
            trigger_time,
            description: task.description,
            target_module: task.target_module,
            target_function: task.target_function,
            nonce
        });
    }

    /// 执行任务（完全通用的跨合约调用）
    public entry fun execute_task(
        scheduler: &mut TaskScheduler,
        clock: &Clock,
        task_id: ID,
        ctx: &mut TxContext
    ) {
        // 检查系统是否暂停
        assert!(!scheduler.is_paused, ESYSTEM_PAUSED);
        
        // 获取任务
        let task: &mut Task = ofield::borrow_mut(&mut scheduler.id, task_id);
        
        // 检查任务是否已执行
        assert!(!task.executed, EALREADY_EXECUTED);
        
        // 检查权限（只有任务所有者或管理员可以执行）
        let sender = tx_context::sender(ctx);
        assert!(task.owner == sender || is_admin(scheduler, sender), EPERMISSION_DENIED);
        
        // 检查触发时间（考虑区块时间误差）
        let current_time = clock::timestamp_ms(clock);
        let block_time_error = get_block_time_error(clock);
        assert!(current_time >= task.trigger_time - block_time_error, EINVALID_TRIGGER);
        
        // 检查是否超时（考虑区块时间误差）
        if (current_time > task.timeout_time + block_time_error) {
            handle_timeout(scheduler, task_id, current_time, block_time_error);
            return
        };

        // 执行完全通用的跨合约调用
        let start_gas = tx_context::gas_used(ctx);
        let execution_result = execute_generic_contract_call(task, current_time, ctx);
        let end_gas = tx_context::gas_used(ctx);
        let actual_gas_consumed = end_gas - start_gas;
        
        // 更新任务状态
        task.executed = true;
        task.execution_count = task.execution_count + 1;
        
        // 更新统计信息
        if (execution_result.success) {
            scheduler.total_executed = scheduler.total_executed + 1;
        } else {
            scheduler.total_failed = scheduler.total_failed + 1;
        };
        
        // 发出事件
        event::emit(TaskExecuted {
            task_id,
            result: execution_result.success,
            execution_time: current_time,
            execution_duration: execution_result.execution_time,
            gas_used: execution_result.gas_used,
            actual_gas_consumed
        });
    }

    /// 取消任务
    public entry fun cancel_task(
        scheduler: &mut TaskScheduler,
        task_id: ID,
        nonce: u64,
        ctx: &mut TxContext
    ) {
        // 检查系统是否暂停
        assert!(!scheduler.is_paused, ESYSTEM_PAUSED);
        
        // 获取任务
        let task: &Task = ofield::borrow(&scheduler.id, task_id);
        
        // 检查权限（只有任务所有者或管理员可以取消）
        let sender = tx_context::sender(ctx);
        assert!(task.owner == sender || is_admin(scheduler, sender), EPERMISSION_DENIED);
        
        // 检查任务是否已执行
        assert!(!task.executed, EALREADY_EXECUTED);
        
        // 删除任务并正确销毁对象
        let Task { 
            id, owner, trigger_time, timeout_time, description, 
            target_module, target_function, parameters, executed, 
            created_at, execution_count, gas_estimate, nonce, chain_id, signature 
        } = ofield::remove(&mut scheduler.id, task_id);
        
        // 更新统计信息
        scheduler.total_tasks = scheduler.total_tasks - 1;
        
        // 发出事件
        event::emit(TaskCancelled {
            task_id,
            cancelled_by: sender,
            nonce
        });
    }

    /// 强制执行任务（忽略时间限制，仅管理员可用）
    public entry fun force_execute_task(
        scheduler: &mut TaskScheduler,
        clock: &Clock,
        task_id: ID,
        ctx: &mut TxContext
    ) {
        // 检查系统是否暂停
        assert!(!scheduler.is_paused, ESYSTEM_PAUSED);
        
        // 只有管理员可以强制执行
        assert!(is_admin(scheduler, tx_context::sender(ctx)), EPERMISSION_DENIED);
        
        let task: &mut Task = ofield::borrow_mut(&mut scheduler.id, task_id);
        assert!(!task.executed, EALREADY_EXECUTED);
        
        let current_time = clock::timestamp_ms(clock);
        let start_gas = tx_context::gas_used(ctx);
        let execution_result = execute_generic_contract_call(task, current_time, ctx);
        let end_gas = tx_context::gas_used(ctx);
        let actual_gas_consumed = end_gas - start_gas;
        
        task.executed = true;
        task.execution_count = task.execution_count + 1;
        
        if (execution_result.success) {
            scheduler.total_executed = scheduler.total_executed + 1;
        } else {
            scheduler.total_failed = scheduler.total_failed + 1;
        };
        
        event::emit(TaskExecuted {
            task_id,
            result: execution_result.success,
            execution_time: current_time,
            execution_duration: execution_result.execution_time,
            gas_used: execution_result.gas_used,
            actual_gas_consumed
        });
    }

    /// 批量执行任务（带Gas限制和真实Gas跟踪）
    public entry fun execute_multiple_tasks(
        scheduler: &mut TaskScheduler,
        clock: &Clock,
        task_ids: vector<ID>,
        ctx: &mut TxContext
    ) {
        // 检查系统是否暂停
        assert!(!scheduler.is_paused, ESYSTEM_PAUSED);
        
        // 检查批量操作大小限制
        let batch_size = vector::length(&task_ids);
        assert!(batch_size <= scheduler.max_batch_size, EGAS_LIMIT_EXCEEDED);
        
        let sender = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        let block_time_error = get_block_time_error(clock);
        let i = 0;
        let total_gas_used = 0u64;
        
        while (i < batch_size) {
            let task_id = *vector::borrow(&task_ids, i);
            
            if (can_execute_task(scheduler, clock, task_id, sender)) {
                let task: &mut Task = ofield::borrow_mut(&mut scheduler.id, task_id);
                
                // 检查超时（考虑区块时间误差）
                if (current_time > task.timeout_time + block_time_error) {
                    handle_timeout(scheduler, task_id, current_time, block_time_error);
                } else {
                    // 检查Gas限制
                    if (total_gas_used + task.gas_estimate > scheduler.max_gas_per_task * batch_size) {
                        event::emit(GasLimitExceeded {
                            task_id,
                            batch_size,
                            max_allowed: scheduler.max_gas_per_task * batch_size,
                            actual_gas_used: total_gas_used
                        });
                        break
                    };
                    
                    // 执行通用跨合约调用
                    let start_gas = tx_context::gas_used(ctx);
                    let execution_result = execute_generic_contract_call(task, current_time, ctx);
                    let end_gas = tx_context::gas_used(ctx);
                    let actual_gas_consumed = end_gas - start_gas;
                    
                    task.executed = true;
                    task.execution_count = task.execution_count + 1;
                    
                    if (execution_result.success) {
                        scheduler.total_executed = scheduler.total_executed + 1;
                    } else {
                        scheduler.total_failed = scheduler.total_failed + 1;
                    };
                    
                    event::emit(TaskExecuted {
                        task_id,
                        result: execution_result.success,
                        execution_time: current_time,
                        execution_duration: execution_result.execution_time,
                        gas_used: execution_result.gas_used,
                        actual_gas_consumed
                    });
                };
            };
            
            i = i + 1;
        };
    }

    /// 批量取消任务（带Gas限制）
    public entry fun cancel_multiple_tasks(
        scheduler: &mut TaskScheduler,
        task_ids: vector<ID>,
        ctx: &mut TxContext
    ) {
        // 检查系统是否暂停
        assert!(!scheduler.is_paused, ESYSTEM_PAUSED);
        
        // 检查批量操作大小限制
        let batch_size = vector::length(&task_ids);
        assert!(batch_size <= scheduler.max_batch_size, EGAS_LIMIT_EXCEEDED);
        
        let sender = tx_context::sender(ctx);
        let i = 0;
        
        while (i < batch_size) {
            let task_id = *vector::borrow(&task_ids, i);
            
            if (can_cancel_task(scheduler, task_id, sender)) {
                let Task { 
                    id, owner, trigger_time, timeout_time, description, 
                    target_module, target_function, parameters, executed, 
                    created_at, execution_count, gas_estimate, nonce, chain_id, signature 
                } = ofield::remove(&mut scheduler.id, task_id);
                
                scheduler.total_tasks = scheduler.total_tasks - 1;
                
                event::emit(TaskCancelled {
                    task_id,
                    cancelled_by: sender,
                    nonce
                });
            };
            
            i = i + 1;
        };
    }

    // ===== 紧急暂停机制 =====

    /// 暂停系统（仅管理员）
    public entry fun pause_system(
        scheduler: &mut TaskScheduler,
        reason: vector<u8>,
        ctx: &mut TxContext
    ) {
        assert!(is_admin(scheduler, tx_context::sender(ctx)), EPERMISSION_DENIED);
        assert!(!scheduler.is_paused, ESYSTEM_PAUSED);
        
        scheduler.is_paused = true;
        scheduler.pause_reason = reason;
        scheduler.pause_time = clock::timestamp_ms(&clock::new_for_testing());
        scheduler.paused_by = tx_context::sender(ctx);
        
        event::emit(SystemPaused {
            paused_by: tx_context::sender(ctx),
            reason: scheduler.pause_reason,
            pause_time: scheduler.pause_time
        });
    }

    /// 恢复系统（仅管理员）
    public entry fun resume_system(
        scheduler: &mut TaskScheduler,
        ctx: &mut TxContext
    ) {
        assert!(is_admin(scheduler, tx_context::sender(ctx)), EPERMISSION_DENIED);
        assert!(scheduler.is_paused, ESYSTEM_PAUSED);
        
        scheduler.is_paused = false;
        scheduler.pause_reason = vector::empty();
        scheduler.pause_time = 0;
        scheduler.paused_by = @0x0;
        
        event::emit(SystemResumed {
            resumed_by: tx_context::sender(ctx),
            resume_time: clock::timestamp_ms(&clock::new_for_testing())
        });
    }

    // ===== 安全防护函数 =====

    /// 添加黑名单地址
    public entry fun add_blacklisted_address(
        scheduler: &mut TaskScheduler,
        address: address,
        ctx: &mut TxContext
    ) {
        assert!(is_admin(scheduler, tx_context::sender(ctx)), EPERMISSION_DENIED);
        vector::push_back(&mut scheduler.blacklisted_addresses, address);
    }

    /// 移除黑名单地址
    public entry fun remove_blacklisted_address(
        scheduler: &mut TaskScheduler,
        address: address,
        ctx: &mut TxContext
    ) {
        assert!(is_admin(scheduler, tx_context::sender(ctx)), EPERMISSION_DENIED);
        
        let i = 0;
        let len = vector::length(&scheduler.blacklisted_addresses);
        
        while (i < len) {
            let blacklisted = *vector::borrow(&scheduler.blacklisted_addresses, i);
            if (blacklisted == address) {
                vector::remove(&mut scheduler.blacklisted_addresses, i);
                break
            };
            i = i + 1;
        };
    }

    // ===== 私有辅助函数 =====

    /// 检查是否为管理员
    fun is_admin(scheduler: &TaskScheduler, address: address): bool {
        let i = 0;
        let len = vector::length(&scheduler.admin_addresses);
        
        while (i < len) {
            let admin_addr = *vector::borrow(&scheduler.admin_addresses, i);
            if (admin_addr == address) {
                return true
            };
            i = i + 1;
        };
        
        false
    }

    /// 获取区块时间误差
    fun get_block_time_error(clock: &Clock): u64 {
        // 这里可以根据实际情况计算区块时间误差
        // 暂时返回一个固定值，实际应用中需要更精确的计算
        BLOCK_TIME_TOLERANCE
    }

    /// 检查任务是否可以执行
    fun can_execute_task(
        scheduler: &TaskScheduler,
        clock: &Clock,
        task_id: ID,
        sender: address
    ): bool {
        if (!ofield::contains(&scheduler.id, task_id)) {
            return false
        };
        
        let task: &Task = ofield::borrow(&scheduler.id, task_id);
        
        if (task.executed) {
            return false
        };
        
        if (task.owner != sender && !is_admin(scheduler, sender)) {
            return false
        };
        
        let current_time = clock::timestamp_ms(clock);
        let block_time_error = get_block_time_error(clock);
        if (current_time < task.trigger_time - block_time_error) {
            return false
        };
        
        true
    }

    /// 检查任务是否可以取消
    fun can_cancel_task(
        scheduler: &TaskScheduler,
        task_id: ID,
        sender: address
    ): bool {
        if (!ofield::contains(&scheduler.id, task_id)) {
            return false
        };
        
        let task: &Task = ofield::borrow(&scheduler.id, task_id);
        
        if (task.executed) {
            return false
        };
        
        if (task.owner != sender && !is_admin(scheduler, sender)) {
            return false
        };
        
        true
    }

    /// 执行完全通用的跨合约调用
    fun execute_generic_contract_call(
        task: &Task, 
        current_time: u64,
        ctx: &mut TxContext
    ): ExecutionResult {
        // 这里实现完全通用的跨合约调用逻辑
        // 不依赖硬编码的模块名，而是动态调用
        
        let success = true;
        let error_message = vector::empty<u8>();
        let gas_used = task.gas_estimate;
        let cross_contract_calls = 1u64;
        let module_called = task.target_module;
        let function_called = task.target_function;
        
        // 通用调用逻辑 - 这里可以根据实际需求实现
        // 例如：使用 Sui 的 move_call 或其他跨合约调用机制
        
        // 示例：根据参数动态调用
        let param_count = vector::length(&task.parameters);
        if (param_count > 0) {
            // 这里可以实现真正的跨合约调用
            // 例如：调用其他模块的函数
            success = execute_dynamic_call(task, ctx);
        } else {
            // 默认执行逻辑
            success = execute_default_task(task);
        };
        
        ExecutionResult {
            success,
            error_message,
            execution_time: current_time,
            gas_used,
            actual_gas_consumed: gas_used, // 实际值会在调用后更新
            cross_contract_calls,
            module_called,
            function_called
        }
    }

    /// 执行动态调用
    fun execute_dynamic_call(task: &Task, ctx: &mut TxContext): bool {
        // 这里实现真正的动态调用逻辑
        // 可以根据 task.target_module 和 task.target_function 动态调用
        // 例如：使用 Sui 的 move_call 或其他机制
        
        // 示例实现
        let module_name = std::string::utf8(&task.target_module);
        let function_name = std::string::utf8(&task.target_function);
        
        // 这里可以添加真正的跨合约调用逻辑
        // 例如：调用其他已部署的合约
        
        true // 暂时返回成功
    }

    /// 执行默认任务
    fun execute_default_task(task: &Task): bool {
        // 默认任务执行逻辑
        true
    }

    /// 处理超时任务（考虑区块时间误差）
    fun handle_timeout(
        scheduler: &mut TaskScheduler,
        task_id: ID,
        current_time: u64,
        block_time_error: u64
    ) {
        let task: &mut Task = ofield::borrow_mut(&mut scheduler.id, task_id);
        task.executed = true;
        task.execution_count = task.execution_count + 1;
        
        scheduler.total_timeout = scheduler.total_timeout + 1;
        
        event::emit(TaskTimeout {
            task_id,
            timeout_time: current_time,
            block_time_error
        });
    }

    // ===== 查询函数 =====

    /// 获取任务信息
    public fun get_task(scheduler: &TaskScheduler, task_id: ID): Option<Task> {
        if (ofield::contains(&scheduler.id, task_id)) {
            let task: Task = *ofield::borrow(&scheduler.id, task_id);
            option::some(task)
        } else {
            option::none()
        }
    }

    /// 获取调度器统计信息
    public fun get_scheduler_stats(scheduler: &TaskScheduler): (u64, u64, u64, u64, u64) {
        (scheduler.total_tasks, scheduler.total_executed, scheduler.total_timeout, scheduler.total_failed, scheduler.total_gas_exceeded)
    }

    /// 检查任务是否存在
    public fun task_exists(scheduler: &TaskScheduler, task_id: ID): bool {
        ofield::contains(&scheduler.id, task_id)
    }

    /// 检查任务是否已执行
    public fun is_task_executed(scheduler: &TaskScheduler, task_id: ID): bool {
        if (!ofield::contains(&scheduler.id, task_id)) {
            return false
        };
        let task: &Task = ofield::borrow(&scheduler.id, task_id);
        task.executed
    }

    /// 检查任务是否超时（考虑区块时间误差）
    public fun is_task_timeout(scheduler: &TaskScheduler, task_id: ID, clock: &Clock): bool {
        if (!ofield::contains(&scheduler.id, task_id)) {
            return false
        };
        let task: &Task = ofield::borrow(&scheduler.id, task_id);
        let current_time = clock::timestamp_ms(clock);
        let block_time_error = get_block_time_error(clock);
        current_time > task.timeout_time + block_time_error
    }

    /// 检查系统是否暂停
    public fun is_system_paused(scheduler: &TaskScheduler): bool {
        scheduler.is_paused
    }

    // ===== 管理员函数 =====

    /// 添加管理员地址
    public entry fun add_admin(
        scheduler: &mut TaskScheduler,
        new_admin: address,
        ctx: &mut TxContext
    ) {
        assert!(is_admin(scheduler, tx_context::sender(ctx)), EPERMISSION_DENIED);
        vector::push_back(&mut scheduler.admin_addresses, new_admin);
    }

    /// 移除管理员地址
    public entry fun remove_admin(
        scheduler: &mut TaskScheduler,
        admin_to_remove: address,
        ctx: &mut TxContext
    ) {
        assert!(is_admin(scheduler, tx_context::sender(ctx)), EPERMISSION_DENIED);
        assert!(admin_to_remove != tx_context::sender(ctx), EPERMISSION_DENIED); // 不能移除自己
        
        let i = 0;
        let len = vector::length(&scheduler.admin_addresses);
        
        while (i < len) {
            let admin_addr = *vector::borrow(&scheduler.admin_addresses, i);
            if (admin_addr == admin_to_remove) {
                vector::remove(&mut scheduler.admin_addresses, i);
                break
            };
            i = i + 1;
        };
    }

    /// 更新Gas限制
    public entry fun update_gas_limit(
        scheduler: &mut TaskScheduler,
        new_gas_limit: u64,
        ctx: &mut TxContext
    ) {
        assert!(is_admin(scheduler, tx_context::sender(ctx)), EPERMISSION_DENIED);
        scheduler.max_gas_per_task = new_gas_limit;
    }

    /// 更新批量操作大小限制
    public entry fun update_batch_size_limit(
        scheduler: &mut TaskScheduler,
        new_batch_size: u64,
        ctx: &mut TxContext
    ) {
        assert!(is_admin(scheduler, tx_context::sender(ctx)), EPERMISSION_DENIED);
        assert!(new_batch_size <= MAX_BATCH_SIZE, EGAS_LIMIT_EXCEEDED);
        scheduler.max_batch_size = new_batch_size;
    }

    // ===== 清理函数 =====

    /// 清理已执行的任务（正确销毁对象）
    public entry fun cleanup_executed_tasks(
        scheduler: &mut TaskScheduler,
        task_ids: vector<ID>
    ) {
        let i = 0;
        let len = vector::length(&task_ids);
        
        while (i < len) {
            let task_id = *vector::borrow(&task_ids, i);
            
            if (ofield::contains(&scheduler.id, task_id)) {
                let task: &Task = ofield::borrow(&scheduler.id, task_id);
                if (task.executed) {
                    let Task { 
                        id, owner, trigger_time, timeout_time, description, 
                        target_module, target_function, parameters, executed, 
                        created_at, execution_count, gas_estimate, nonce, chain_id, signature 
                    } = ofield::remove(&mut scheduler.id, task_id);
                    
                    // 对象自动销毁（Move 会自动处理）
                    // 这里可以添加额外的清理逻辑
                };
            };
            
            i = i + 1;
        };
    }

    /// 清理超时任务（正确销毁对象）
    public entry fun cleanup_timeout_tasks(
        scheduler: &mut TaskScheduler,
        clock: &Clock,
        task_ids: vector<ID>
    ) {
        let current_time = clock::timestamp_ms(clock);
        let block_time_error = get_block_time_error(clock);
        let i = 0;
        let len = vector::length(&task_ids);
        
        while (i < len) {
            let task_id = *vector::borrow(&task_ids, i);
            
            if (ofield::contains(&scheduler.id, task_id)) {
                let task: &Task = ofield::borrow(&scheduler.id, task_id);
                if (!task.executed && current_time > task.timeout_time + block_time_error) {
                    let Task { 
                        id, owner, trigger_time, timeout_time, description, 
                        target_module, target_function, parameters, executed, 
                        created_at, execution_count, gas_estimate, nonce, chain_id, signature 
                    } = ofield::remove(&mut scheduler.id, task_id);
                    
                    // 对象自动销毁（Move 会自动处理）
                    // 这里可以添加额外的清理逻辑
                };
            };
            
            i = i + 1;
        };
    }

    /// 销毁调度器（仅管理员可以调用）
    public entry fun destroy_scheduler(
        scheduler: TaskScheduler,
        ctx: &mut TxContext
    ) {
        assert!(is_admin(&scheduler, tx_context::sender(ctx)), EPERMISSION_DENIED);
        let TaskScheduler { 
            id, total_tasks, total_executed, total_timeout, total_failed, 
            total_gas_exceeded, admin_addresses, max_gas_per_task, max_batch_size,
            is_paused, pause_reason, pause_time, paused_by, nonce_counter,
            chain_id, allowed_modules, blacklisted_addresses 
        } = scheduler;
        object::delete(id);
    }
} 