#[test_only]
module task_scheduler::scheduler_tests {
    use sui::test_scenario::{Self, Scenario};
    use sui::clock::{Self, Clock};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use task_scheduler::scheduler::{Self, TaskScheduler, TaskIDGenerator, Task};
    use std::vector;

    // 测试地址
    const ADMIN: address = @0xA;
    const USER1: address = @0xB;
    const USER2: address = @0xC;
    const ADMIN2: address = @0xD;

    // ===== 测试辅助函数 =====

    fun setup_test(): Scenario {
        let scenario = test_scenario::begin(ADMIN);
        
        // 创建时钟对象
        let clock = Clock {
            id: object::new_for_testing(),
            timestamp_ms: 1000
        };
        test_scenario::next_tx(&mut scenario, ADMIN);
        transfer::share_object(clock);
        
        // 创建调度器（带管理员地址和配置）
        test_scenario::next_tx(&mut scenario, ADMIN);
        let admin_addresses = vector[ADMIN, ADMIN2];
        scheduler::create_scheduler(
            admin_addresses,
            1000000, // max_gas_per_task
            50, // max_batch_size
            test_scenario::ctx(&mut scenario)
        );
        
        // 创建ID生成器
        test_scenario::next_tx(&mut scenario, ADMIN);
        scheduler::create_id_generator(test_scenario::ctx(&mut scenario));
        
        scenario
    }

    // ===== 基础功能测试 =====

    #[test]
    fun test_create_scheduler() {
        let scenario = test_scenario::begin(ADMIN);
        let admin_addresses = vector[ADMIN];
        scheduler::create_scheduler(
            admin_addresses,
            1000000,
            50,
            test_scenario::ctx(&mut scenario)
        );
        test_scenario::end(scenario);
    }

    #[test]
    fun test_create_id_generator() {
        let scenario = test_scenario::begin(ADMIN);
        scheduler::create_id_generator(test_scenario::ctx(&mut scenario));
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_task() {
        let scenario = setup_test();
        
        // 获取时钟和调度器
        let clock = test_scenario::take_shared<Clock>(&scenario);
        let scheduler = test_scenario::take_shared<TaskScheduler>(&scenario);
        let generator = test_scenario::take_shared<TaskIDGenerator>(&scenario);
        
        // 注册任务
        test_scenario::next_tx(&mut scenario, USER1);
        scheduler::register_task(
            &mut scheduler,
            &mut generator,
            &clock,
            2000, // 触发时间
            3600000, // 超时时间（1小时）
            b"测试任务", // 描述
            b"email_service", // 目标模块
            b"send_email", // 目标函数
            vector[b"recipient@example.com", b"Hello World"], // 参数
            50000, // gas_estimate
            test_scenario::ctx(&mut scenario)
        );
        
        // 验证任务已注册
        let (total_tasks, total_executed, total_timeout, total_failed, total_gas_exceeded) = scheduler::get_scheduler_stats(&scheduler);
        assert!(total_tasks == 1, 0);
        assert!(total_executed == 0, 0);
        assert!(total_timeout == 0, 0);
        assert!(total_failed == 0, 0);
        assert!(total_gas_exceeded == 0, 0);
        
        // 清理
        test_scenario::return_shared(clock);
        test_scenario::return_shared(scheduler);
        test_scenario::return_shared(generator);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_execute_task() {
        let scenario = setup_test();
        
        // 获取时钟和调度器
        let clock = test_scenario::take_shared<Clock>(&scenario);
        let scheduler = test_scenario::take_shared<TaskScheduler>(&scenario);
        let generator = test_scenario::take_shared<TaskIDGenerator>(&scenario);
        
        // 注册任务
        test_scenario::next_tx(&mut scenario, USER1);
        scheduler::register_task(
            &mut scheduler,
            &mut generator,
            &clock,
            2000, // 触发时间
            3600000, // 超时时间
            b"测试任务",
            b"email_service",
            b"send_email",
            vector[b"recipient@example.com"],
            50000, // gas_estimate
            test_scenario::ctx(&mut scenario)
        );
        
        // 更新时钟时间到触发时间之后
        let mut clock_mut = clock;
        clock::set_timestamp_ms(&mut clock_mut, 2500);
        
        // 执行任务
        test_scenario::next_tx(&mut scenario, USER1);
        scheduler::execute_task(
            &mut scheduler,
            &clock_mut,
            object::id_from_address(USER1, 0), // 任务ID
            test_scenario::ctx(&mut scenario)
        );
        
        // 验证任务已执行
        let (total_tasks, total_executed, total_timeout, total_failed, total_gas_exceeded) = scheduler::get_scheduler_stats(&scheduler);
        assert!(total_tasks == 1, 0);
        assert!(total_executed == 1, 0);
        assert!(total_timeout == 0, 0);
        assert!(total_failed == 0, 0);
        assert!(total_gas_exceeded == 0, 0);
        
        // 清理
        test_scenario::return_shared(clock_mut);
        test_scenario::return_shared(scheduler);
        test_scenario::return_shared(generator);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_cancel_task() {
        let scenario = setup_test();
        
        // 获取时钟和调度器
        let clock = test_scenario::take_shared<Clock>(&scenario);
        let scheduler = test_scenario::take_shared<TaskScheduler>(&scenario);
        let generator = test_scenario::take_shared<TaskIDGenerator>(&scenario);
        
        // 注册任务
        test_scenario::next_tx(&mut scenario, USER1);
        scheduler::register_task(
            &mut scheduler,
            &mut generator,
            &clock,
            2000,
            3600000,
            b"测试任务",
            b"email_service",
            b"send_email",
            vector[b"recipient@example.com"],
            50000,
            test_scenario::ctx(&mut scenario)
        );
        
        // 取消任务
        test_scenario::next_tx(&mut scenario, USER1);
        scheduler::cancel_task(
            &mut scheduler,
            object::id_from_address(USER1, 0),
            test_scenario::ctx(&mut scenario)
        );
        
        // 验证任务已取消
        let (total_tasks, total_executed, total_timeout, total_failed, total_gas_exceeded) = scheduler::get_scheduler_stats(&scheduler);
        assert!(total_tasks == 0, 0);
        assert!(total_executed == 0, 0);
        assert!(total_timeout == 0, 0);
        assert!(total_failed == 0, 0);
        assert!(total_gas_exceeded == 0, 0);
        
        // 清理
        test_scenario::return_shared(clock);
        test_scenario::return_shared(scheduler);
        test_scenario::return_shared(generator);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_timeout_task() {
        let scenario = setup_test();
        
        // 获取时钟和调度器
        let clock = test_scenario::take_shared<Clock>(&scenario);
        let scheduler = test_scenario::take_shared<TaskScheduler>(&scenario);
        let generator = test_scenario::take_shared<TaskIDGenerator>(&scenario);
        
        // 注册任务（超时时间很短）
        test_scenario::next_tx(&mut scenario, USER1);
        scheduler::register_task(
            &mut scheduler,
            &mut generator,
            &clock,
            2000, // 触发时间
            100, // 超时时间很短
            b"测试任务",
            b"email_service",
            b"send_email",
            vector[b"recipient@example.com"],
            50000,
            test_scenario::ctx(&mut scenario)
        );
        
        // 更新时钟时间到超时时间之后
        let mut clock_mut = clock;
        clock::set_timestamp_ms(&mut clock_mut, 2500);
        
        // 执行任务（应该触发超时）
        test_scenario::next_tx(&mut scenario, USER1);
        scheduler::execute_task(
            &mut scheduler,
            &clock_mut,
            object::id_from_address(USER1, 0),
            test_scenario::ctx(&mut scenario)
        );
        
        // 验证任务已超时
        let (total_tasks, total_executed, total_timeout, total_failed, total_gas_exceeded) = scheduler::get_scheduler_stats(&scheduler);
        assert!(total_tasks == 1, 0);
        assert!(total_executed == 0, 0);
        assert!(total_timeout == 1, 0);
        assert!(total_failed == 0, 0);
        assert!(total_gas_exceeded == 0, 0);
        
        // 清理
        test_scenario::return_shared(clock_mut);
        test_scenario::return_shared(scheduler);
        test_scenario::return_shared(generator);
        test_scenario::end(scenario);
    }

    // ===== 管理员权限测试 =====

    #[test]
    fun test_admin_force_execute() {
        let scenario = setup_test();
        
        let clock = test_scenario::take_shared<Clock>(&scenario);
        let scheduler = test_scenario::take_shared<TaskScheduler>(&scenario);
        let generator = test_scenario::take_shared<TaskIDGenerator>(&scenario);
        
        // 注册任务
        test_scenario::next_tx(&mut scenario, USER1);
        scheduler::register_task(
            &mut scheduler,
            &mut generator,
            &clock,
            2000,
            3600000,
            b"测试任务",
            b"email_service",
            b"send_email",
            vector[b"recipient@example.com"],
            50000,
            test_scenario::ctx(&mut scenario)
        );
        
        // 管理员强制执行任务（忽略时间限制）
        test_scenario::next_tx(&mut scenario, ADMIN);
        scheduler::force_execute_task(
            &mut scheduler,
            &clock,
            object::id_from_address(USER1, 0),
            test_scenario::ctx(&mut scenario)
        );
        
        // 验证任务已执行
        let (total_tasks, total_executed, total_timeout, total_failed, total_gas_exceeded) = scheduler::get_scheduler_stats(&scheduler);
        assert!(total_tasks == 1, 0);
        assert!(total_executed == 1, 0);
        assert!(total_timeout == 0, 0);
        assert!(total_failed == 0, 0);
        assert!(total_gas_exceeded == 0, 0);
        
        test_scenario::return_shared(clock);
        test_scenario::return_shared(scheduler);
        test_scenario::return_shared(generator);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_admin_add_remove() {
        let scenario = setup_test();
        
        let scheduler = test_scenario::take_shared<TaskScheduler>(&scenario);
        
        // 添加新管理员
        test_scenario::next_tx(&mut scenario, ADMIN);
        scheduler::add_admin(
            &mut scheduler,
            @0xE, // 新管理员地址
            test_scenario::ctx(&mut scenario)
        );
        
        // 移除管理员
        test_scenario::next_tx(&mut scenario, ADMIN);
        scheduler::remove_admin(
            &mut scheduler,
            ADMIN2, // 移除ADMIN2
            test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::return_shared(scheduler);
        test_scenario::end(scenario);
    }

    // ===== 批量操作测试 =====

    #[test]
    fun test_batch_operations() {
        let scenario = setup_test();
        
        // 获取时钟和调度器
        let clock = test_scenario::take_shared<Clock>(&scenario);
        let scheduler = test_scenario::take_shared<TaskScheduler>(&scenario);
        let generator = test_scenario::take_shared<TaskIDGenerator>(&scenario);
        
        // 注册多个任务
        test_scenario::next_tx(&mut scenario, USER1);
        scheduler::register_task(
            &mut scheduler,
            &mut generator,
            &clock,
            2000,
            3600000,
            b"任务1",
            b"email_service",
            b"send_email",
            vector[b"user1@example.com"],
            50000,
            test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::next_tx(&mut scenario, USER1);
        scheduler::register_task(
            &mut scheduler,
            &mut generator,
            &clock,
            3000,
            3600000,
            b"任务2",
            b"payment_service",
            b"process_payment",
            vector[b"100", b"USD"],
            75000,
            test_scenario::ctx(&mut scenario)
        );
        
        // 更新时钟时间
        let mut clock_mut = clock;
        clock::set_timestamp_ms(&mut clock_mut, 2500);
        
        // 批量执行任务
        test_scenario::next_tx(&mut scenario, USER1);
        let task_ids = vector[object::id_from_address(USER1, 0), object::id_from_address(USER1, 1)];
        scheduler::execute_multiple_tasks(
            &mut scheduler,
            &clock_mut,
            task_ids,
            test_scenario::ctx(&mut scenario)
        );
        
        // 验证批量执行结果
        let (total_tasks, total_executed, total_timeout, total_failed, total_gas_exceeded) = scheduler::get_scheduler_stats(&scheduler);
        assert!(total_tasks == 2, 0);
        assert!(total_executed == 1, 0); // 只有第一个任务可以执行
        assert!(total_timeout == 0, 0);
        assert!(total_failed == 0, 0);
        assert!(total_gas_exceeded == 0, 0);
        
        // 清理
        test_scenario::return_shared(clock_mut);
        test_scenario::return_shared(scheduler);
        test_scenario::return_shared(generator);
        test_scenario::end(scenario);
    }

    // ===== Gas限制测试 =====

    #[test]
    #[expected_failure(abort_code = scheduler::EGAS_LIMIT_EXCEEDED)]
    fun test_gas_limit_exceeded() {
        let scenario = setup_test();
        
        let scheduler = test_scenario::take_shared<TaskScheduler>(&scenario);
        let generator = test_scenario::take_shared<TaskIDGenerator>(&scenario);
        let clock = test_scenario::take_shared<Clock>(&scenario);
        
        // 尝试注册超过Gas限制的任务
        test_scenario::next_tx(&mut scenario, USER1);
        scheduler::register_task(
            &mut scheduler,
            &mut generator,
            &clock,
            2000,
            3600000,
            b"测试任务",
            b"email_service",
            b"send_email",
            vector[b"recipient@example.com"],
            2000000, // 超过Gas限制
            test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::return_shared(scheduler);
        test_scenario::return_shared(generator);
        test_scenario::return_shared(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = scheduler::EGAS_LIMIT_EXCEEDED)]
    fun test_batch_size_limit() {
        let scenario = setup_test();
        
        let scheduler = test_scenario::take_shared<TaskScheduler>(&scenario);
        
        // 尝试批量操作超过大小限制
        test_scenario::next_tx(&mut scenario, USER1);
        let large_task_ids = vector::empty<ID>();
        let i = 0;
        while (i < 100) { // 超过50的限制
            vector::push_back(&mut large_task_ids, object::id_from_address(USER1, i));
            i = i + 1;
        };
        
        scheduler::execute_multiple_tasks(
            &mut scheduler,
            &clock::new_for_testing(),
            large_task_ids,
            test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::return_shared(scheduler);
        test_scenario::end(scenario);
    }

    // ===== 错误处理测试 =====

    #[test]
    #[expected_failure(abort_code = scheduler::EINVALID_TIMESTAMP)]
    fun test_invalid_timestamp() {
        let scenario = setup_test();
        
        let clock = test_scenario::take_shared<Clock>(&scenario);
        let scheduler = test_scenario::take_shared<TaskScheduler>(&scenario);
        let generator = test_scenario::take_shared<TaskIDGenerator>(&scenario);
        
        // 尝试注册过去时间的任务
        test_scenario::next_tx(&mut scenario, USER1);
        scheduler::register_task(
            &mut scheduler,
            &mut generator,
            &clock,
            500, // 过去的时间
            3600000,
            b"测试任务",
            b"email_service",
            b"send_email",
            vector[b"recipient@example.com"],
            50000,
            test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::return_shared(clock);
        test_scenario::return_shared(scheduler);
        test_scenario::return_shared(generator);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = scheduler::EALREADY_EXECUTED)]
    fun test_execute_already_executed_task() {
        let scenario = setup_test();
        
        let clock = test_scenario::take_shared<Clock>(&scenario);
        let scheduler = test_scenario::take_shared<TaskScheduler>(&scenario);
        let generator = test_scenario::take_shared<TaskIDGenerator>(&scenario);
        
        // 注册任务
        test_scenario::next_tx(&mut scenario, USER1);
        scheduler::register_task(
            &mut scheduler,
            &mut generator,
            &clock,
            2000,
            3600000,
            b"测试任务",
            b"email_service",
            b"send_email",
            vector[b"recipient@example.com"],
            50000,
            test_scenario::ctx(&mut scenario)
        );
        
        // 更新时钟时间
        let mut clock_mut = clock;
        clock::set_timestamp_ms(&mut clock_mut, 2500);
        
        // 第一次执行
        test_scenario::next_tx(&mut scenario, USER1);
        scheduler::execute_task(
            &mut scheduler,
            &clock_mut,
            object::id_from_address(USER1, 0),
            test_scenario::ctx(&mut scenario)
        );
        
        // 尝试再次执行（应该失败）
        test_scenario::next_tx(&mut scenario, USER1);
        scheduler::execute_task(
            &mut scheduler,
            &clock_mut,
            object::id_from_address(USER1, 0),
            test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::return_shared(clock_mut);
        test_scenario::return_shared(scheduler);
        test_scenario::return_shared(generator);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = scheduler::EPERMISSION_DENIED)]
    fun test_unauthorized_execution() {
        let scenario = setup_test();
        
        let clock = test_scenario::take_shared<Clock>(&scenario);
        let scheduler = test_scenario::take_shared<TaskScheduler>(&scenario);
        let generator = test_scenario::take_shared<TaskIDGenerator>(&scenario);
        
        // USER1 注册任务
        test_scenario::next_tx(&mut scenario, USER1);
        scheduler::register_task(
            &mut scheduler,
            &mut generator,
            &clock,
            2000,
            3600000,
            b"测试任务",
            b"email_service",
            b"send_email",
            vector[b"recipient@example.com"],
            50000,
            test_scenario::ctx(&mut scenario)
        );
        
        // 更新时钟时间
        let mut clock_mut = clock;
        clock::set_timestamp_ms(&mut clock_mut, 2500);
        
        // USER2 尝试执行 USER1 的任务（应该失败）
        test_scenario::next_tx(&mut scenario, USER2);
        scheduler::execute_task(
            &mut scheduler,
            &clock_mut,
            object::id_from_address(USER1, 0),
            test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::return_shared(clock_mut);
        test_scenario::return_shared(scheduler);
        test_scenario::return_shared(generator);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = scheduler::EINVALID_TRIGGER)]
    fun test_execute_before_trigger_time() {
        let scenario = setup_test();
        
        let clock = test_scenario::take_shared<Clock>(&scenario);
        let scheduler = test_scenario::take_shared<TaskScheduler>(&scenario);
        let generator = test_scenario::take_shared<TaskIDGenerator>(&scenario);
        
        // 注册任务
        test_scenario::next_tx(&mut scenario, USER1);
        scheduler::register_task(
            &mut scheduler,
            &mut generator,
            &clock,
            2000,
            3600000,
            b"测试任务",
            b"email_service",
            b"send_email",
            vector[b"recipient@example.com"],
            50000,
            test_scenario::ctx(&mut scenario)
        );
        
        // 尝试在触发时间之前执行（应该失败）
        test_scenario::next_tx(&mut scenario, USER1);
        scheduler::execute_task(
            &mut scheduler,
            &clock,
            object::id_from_address(USER1, 0),
            test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::return_shared(clock);
        test_scenario::return_shared(scheduler);
        test_scenario::return_shared(generator);
        test_scenario::end(scenario);
    }

    // ===== 跨合约调用测试 =====

    #[test]
    fun test_cross_contract_calls() {
        let scenario = setup_test();
        
        let clock = test_scenario::take_shared<Clock>(&scenario);
        let scheduler = test_scenario::take_shared<TaskScheduler>(&scenario);
        let generator = test_scenario::take_shared<TaskIDGenerator>(&scenario);
        
        // 测试不同类型的跨合约调用
        test_scenario::next_tx(&mut scenario, USER1);
        scheduler::register_task(
            &mut scheduler,
            &mut generator,
            &clock,
            2000,
            3600000,
            b"邮件任务",
            b"email_service",
            b"send_email",
            vector[b"user@example.com", b"subject", b"content"],
            50000,
            test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::next_tx(&mut scenario, USER1);
        scheduler::register_task(
            &mut scheduler,
            &mut generator,
            &clock,
            2000,
            3600000,
            b"支付任务",
            b"payment_service",
            b"process_payment",
            vector[b"100", b"USD", b"recipient"],
            75000,
            test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::next_tx(&mut scenario, USER1);
        scheduler::register_task(
            &mut scheduler,
            &mut generator,
            &clock,
            2000,
            3600000,
            b"通知任务",
            b"notification_service",
            b"send_push",
            vector[b"user_id", b"message"],
            30000,
            test_scenario::ctx(&mut scenario)
        );
        
        // 更新时钟时间
        let mut clock_mut = clock;
        clock::set_timestamp_ms(&mut clock_mut, 2500);
        
        // 执行所有任务
        test_scenario::next_tx(&mut scenario, USER1);
        let task_ids = vector[
            object::id_from_address(USER1, 0),
            object::id_from_address(USER1, 1),
            object::id_from_address(USER1, 2)
        ];
        scheduler::execute_multiple_tasks(
            &mut scheduler,
            &clock_mut,
            task_ids,
            test_scenario::ctx(&mut scenario)
        );
        
        // 验证所有任务都已执行
        let (total_tasks, total_executed, total_timeout, total_failed, total_gas_exceeded) = scheduler::get_scheduler_stats(&scheduler);
        assert!(total_tasks == 3, 0);
        assert!(total_executed == 3, 0);
        assert!(total_timeout == 0, 0);
        assert!(total_failed == 0, 0);
        assert!(total_gas_exceeded == 0, 0);
        
        test_scenario::return_shared(clock_mut);
        test_scenario::return_shared(scheduler);
        test_scenario::return_shared(generator);
        test_scenario::end(scenario);
    }

    // ===== 清理功能测试 =====

    #[test]
    fun test_cleanup_timeout_tasks() {
        let scenario = setup_test();
        
        let clock = test_scenario::take_shared<Clock>(&scenario);
        let scheduler = test_scenario::take_shared<TaskScheduler>(&scenario);
        let generator = test_scenario::take_shared<TaskIDGenerator>(&scenario);
        
        // 注册任务
        test_scenario::next_tx(&mut scenario, USER1);
        scheduler::register_task(
            &mut scheduler,
            &mut generator,
            &clock,
            2000,
            100, // 短超时时间
            b"测试任务",
            b"email_service",
            b"send_email",
            vector[b"recipient@example.com"],
            50000,
            test_scenario::ctx(&mut scenario)
        );
        
        // 更新时钟时间到超时之后
        let mut clock_mut = clock;
        clock::set_timestamp_ms(&mut clock_mut, 2500);
        
        // 清理超时任务
        test_scenario::next_tx(&mut scenario, USER1);
        let task_ids = vector[object::id_from_address(USER1, 0)];
        scheduler::cleanup_timeout_tasks(
            &mut scheduler,
            &clock_mut,
            task_ids
        );
        
        // 验证超时任务已清理
        let (total_tasks, total_executed, total_timeout, total_failed, total_gas_exceeded) = scheduler::get_scheduler_stats(&scheduler);
        assert!(total_tasks == 0, 0);
        assert!(total_executed == 0, 0);
        assert!(total_timeout == 0, 0);
        assert!(total_failed == 0, 0);
        assert!(total_gas_exceeded == 0, 0);
        
        test_scenario::return_shared(clock_mut);
        test_scenario::return_shared(scheduler);
        test_scenario::return_shared(generator);
        test_scenario::end(scenario);
    }
} 