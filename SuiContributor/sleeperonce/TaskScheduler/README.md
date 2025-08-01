# 任务调度智能合约 Task Scheduler (Sui Move)

---

## 简介 | Introduction

本合约是一个面向 Sui 区块链的通用任务调度工具，支持注册、取消、执行、批量操作、跨合约调用、Gas 管控、权限与安全防护等生产级功能。适用于自动化定时任务、链上服务编排、跨模块自动执行等场景。

This contract is a general-purpose task scheduler for the Sui blockchain. It supports registering, canceling, executing, batch operations, cross-contract calls, gas management, permission and security controls. It is suitable for automated scheduled tasks, on-chain service orchestration, and cross-module automation.

---

## 主要功能 | Key Features

- 完整的任务注册、取消、执行、批量操作流程
- 支持动态对象字段存储任务，ID 唯一安全
- 集成 Sui Clock 对象进行时间校验
- 支持完全通用的跨合约动态调用
- 实时跟踪实际 Gas 消耗，防止超限
- 管理员权限与黑名单机制
- 紧急暂停与恢复系统
- 重放攻击与跨链调用防护
- 全面输入参数验证
- 事件日志追踪所有关键操作

- Full register/cancel/execute/batch workflow
- Dynamic object fields for secure task storage (unique ID)
- Integrated Sui Clock for time validation
- Fully generic cross-contract dynamic invocation
- Real gas usage tracking, gas limit enforcement
- Admin and blacklist system
- Emergency pause/resume
- Replay attack and cross-chain call protection
- Comprehensive input validation
- Event logs for all key actions

---

## 快速使用 | Quick Start

### 1. 部署合约 | Deploy Contract

```bash
cd scheduleDemo
sui move build
```

### 2. 初始化调度器 | Initialize Scheduler

```move
// 管理员地址、Gas与批量限制、链ID、允许的模块白名单
scheduler::create_scheduler(
    admin_addresses,         // vector<address>
    max_gas_per_task,        // u64
    max_batch_size,          // u64
    chain_id,                // u64
    allowed_modules,         // vector<vector<u8>>
    ctx
);
```

### 3. 注册任务 | Register Task

```move
scheduler::register_task(
    &mut scheduler,
    &mut generator,
    &clock,
    trigger_time,            // u64
    timeout_duration,        // u64
    description,             // vector<u8>
    target_module,           // vector<u8>
    target_function,         // vector<u8>
    parameters,              // vector<vector<u8>>
    gas_estimate,            // u64
    nonce,                   // u64
    signature,               // vector<u8>
    ctx
);
```

### 4. 执行/取消/批量操作 | Execute/Cancel/Batch

```move
scheduler::execute_task(&mut scheduler, &clock, task_id, ctx);
scheduler::cancel_task(&mut scheduler, task_id, nonce, ctx);
scheduler::execute_multiple_tasks(&mut scheduler, &clock, task_ids, ctx);
scheduler::cancel_multiple_tasks(&mut scheduler, task_ids, ctx);
```

### 5. 管理员操作 | Admin Actions

```move
scheduler::pause_system(&mut scheduler, reason, ctx);
scheduler::resume_system(&mut scheduler, ctx);
scheduler::add_admin(&mut scheduler, new_admin, ctx);
scheduler::remove_admin(&mut scheduler, admin_to_remove, ctx);
scheduler::add_blacklisted_address(&mut scheduler, address, ctx);
scheduler::remove_blacklisted_address(&mut scheduler, address, ctx);
```

---

## 事件与安全 | Events & Security

- 所有操作均有事件日志，便于链上追踪与审计
- 支持紧急暂停、黑名单、重放攻击防护、跨链调用白名单
- 输入参数均有严格校验，防止恶意数据

All actions emit events for on-chain tracking and audit.
Supports emergency pause, blacklist, replay attack protection, cross-chain call whitelist.
All input parameters are strictly validated to prevent malicious data.

---

## 适用场景 | Use Cases

- 自动化定时任务（如定时转账、定时通知）
- 跨模块/跨合约服务编排
- 链上自动化运维与批量操作

- Automated scheduled tasks (e.g., scheduled transfers, notifications)
- Cross-module/cross-contract service orchestration
- On-chain automation and batch operations

---

## 贡献与反馈 | Contribution & Feedback

如需定制功能或发现问题，欢迎提交 Issue 或 PR。
For custom features or bug reports, please submit an Issue or PR. 