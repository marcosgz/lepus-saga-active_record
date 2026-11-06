# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.3.1 - Unreleased
* Fixed: executions list in time order when their ids are not time-ordered (e.g. random UUIDv4): `list_executions` sorts and pages by (sort value, id) with `after`, `executions_for_resource` and `recent_first` order by started_at, then id
* Added: the `duration_ms` bigint column, the `sort`/`direction`/`after` options of `list_executions` (keyset paging in at most two index-friendly queries, executions without a duration last) and the `finished_from`/`finished_to` filters
* Changed: the `from`/`to` filters and the series' starts use started_at; `lepus-saga ~> 0.3.1` is required
* Changed: dashboard indexes folded into the install migration (pre-release): `lepus:saga:install` indexes `saga_executions (started_at, id)`, `(duration_ms, id)`, `(finished_at)`, `(saga_name, started_at)`, `(status, started_at)`, `(partition, started_at)` and the resource index on `(resource_type, resource_id, started_at)`; the created_at indexes and the `lepus:saga:dashboard_indexes` generator are gone

## 0.3.0 - Unreleased
* Added: brand mark and README logo
* Added: `Lepus::Saga::Stores::ActiveRecord`, selected with `Lepus::Saga.configure { |c| c.store = :active_record }`
* Added: `Lepus::Saga::ActiveRecord::Execution` and `StepAttempt` models (UUIDv7 ids, json context, read scopes) on the `saga_executions` and `saga_step_attempts` tables
* Added: `rails g lepus:saga:install` (moved from lepus-saga): `failure_reason` is `text` and there is no `lock_version` column
* Changed: optimistic locking is off, so a legacy `lock_version` column (tables created before the generator) is ignored; `resume_count` is incremented atomically
* Added: `Execution.prune(finished_before:)` deletes completed executions and their step attempts in batches
* Changed: the resource index is `(resource_type, resource_id, created_at)`, which serves `executions_for_resource`, and `activerecord >= 8.0` is required
* Added: the optional query methods of the store contract (`list_executions`, `count_executions`, `execution_series`, `step_latency`, `failure_summary`, `saga_names`) in portable SQL, with time buckets and percentiles computed in Ruby over at most `max_rows` rows; `queries?` is true
* Added: `lepus:saga:install` indexes `saga_executions (saga_name, created_at)`, `(status, created_at)`, `(finished_at)` and `saga_step_attempts (started_at)`, `(error_class, started_at)`
* Added: `rails g lepus:saga:dashboard_indexes` adds those indexes to existing tables
* Added: the `current_step` filter of `list_executions` and `count_executions`
* Added: the `progress_from`/`progress_to` and `error_class`/`error_step`/`error_from`/`error_to` filters of `list_executions` and `count_executions`, and `execution_count` on `failure_summary` rows
