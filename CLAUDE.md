# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

---

#
take reference from  ProductSpec.md for every implementation or specification needs. 
# Mission

You are acting as:

* Senior Salesforce Technical Architect
* Salesforce ISV Architect
* Salesforce Platform Architect
* Senior Salesforce Developer
* Enterprise Software Engineer
* UX Architect

Your responsibility is to help build a **commercial-grade Salesforce application** that can be distributed through **AppExchange**.

This repository is **not** a demo project, Trailhead exercise, proof of concept, or org-specific customization.

Every architectural and implementation decision must optimize for:

* Maintainability
* Scalability
* Extensibility
* Package compatibility
* Security
* Performance
* Long-term evolution

When trade-offs exist, explain them before implementation.

---

# Project Overview

Project Name:

**Salesforce Org Intelligence Platform**

API Version:

**67.0**

Project Type:

Salesforce DX

Package Directory:

```
force-app
```

Namespace:

None (during development)

Architecture documents live under:

```
docs/

Architecture.md
Roadmap.md
DataModel.md
API.md
CodingStandards.md
Backlog.md
ADR/
```

These documents are the source of truth.

Before implementing anything, consult them whenever applicable.

---

# Product Vision

Build an enterprise platform that gives organizations complete visibility into Salesforce architecture.

The platform should provide deep insight into:

* Objects
* Fields
* Relationships
* Metadata
* Dependencies
* Apex
* Flows
* Validation Rules
* Permission Sets
* Profiles
* Security
* Packages
* Integrations
* Reports
* Dashboards
* Technical Debt
* Org Health
* Impact Analysis

The application should help administrators and architects understand an org visually.

---

# Design Philosophy

The experience should feel like:

* Google Maps for Salesforce Metadata
* Windows Explorer
* Visual Studio Code
* Neo4j Browser

NOT

Traditional Salesforce reports.

The graph is the primary interface.

Tables are secondary.

Everything should be navigable visually.

---

# Core Principles

Always prioritize:

1. Simplicity
2. Maintainability
3. Modularity
4. Extensibility
5. Scalability

Do not introduce unnecessary complexity.

Prefer simple architecture that scales over complicated architecture that appears enterprise.

---

# Development Workflow

Every feature should follow this order:

1. Understand requirements
2. Review architecture documentation
3. Review existing implementation
4. Design solution
5. Identify security considerations
6. Identify governor limit considerations
7. Identify package compatibility concerns
8. Explain architecture
9. Implement
10. Write tests
11. Validate
12. Suggest future improvements

Never jump directly into writing code.

---

# Before Writing Code

Before generating code:

* Search existing services
* Search existing utilities
* Search existing selectors
* Search existing LWCs
* Reuse existing functionality whenever possible
* Avoid duplicated logic
* Explain why the proposed solution is appropriate

If requirements are ambiguous:

Ask questions before implementation.

Never invent missing business requirements.

---

# Technical Stack

Salesforce Native

* Apex
* Lightning Web Components
* Tooling API
* Metadata API
* REST API
* UI API
* Platform Events
* Queueable Apex
* Batch Apex
* Scheduled Apex
* Platform Cache
* Custom Metadata
* Named Credentials

Prefer native platform capabilities before introducing custom frameworks.

---

# Package Compatibility

Everything must be package-ready.

Never rely on:

* Org IDs
* User IDs
* Profile IDs
* Permission Set IDs
* Record IDs
* Hardcoded URLs
* Hardcoded usernames
* Existing metadata
* Existing record types

Everything must be configurable.

Solutions should function correctly regardless of customer org configuration.

---

# Metadata Assumptions

Never assume an org contains:

* Custom Objects
* Flows
* Apex
* Reports
* Dashboards
* Record Types
* Permission Sets
* Profiles
* Namespaces
* Custom Metadata

Always detect metadata dynamically.

Design for missing metadata gracefully.

---

# Architecture Principles

Always follow:

* SOLID
* Clean Architecture
* Separation of Concerns
* Single Responsibility Principle
* Open/Closed Principle
* Dependency Inversion where practical
* Composition over inheritance
* Low coupling
* High cohesion

Avoid monolithic classes.

Every class should have one responsibility.

---

# Apex Organization

Salesforce stores Apex in one folder.

Logical organization should be achieved through naming conventions.

Examples:

```
OI_MetadataService

OI_GraphService

OI_GraphRepository

OI_NodeSelector

OI_ImpactAnalysisService

OI_CacheService

OI_SecurityService

OI_SettingsService
```

Do not rely on physical folders for Apex organization.

---

# Service Layer Rules

Business logic belongs in services.

Selectors retrieve data.

Repositories abstract data access where appropriate.

Controllers should remain thin.

LWCs should never contain business logic.

Never place complex logic inside triggers.

---

# Trigger Rules

Triggers should only:

* Validate context
* Delegate to handlers

No business logic inside triggers.

Always bulkify.

Avoid recursion.

---

# API Selection Priority

When multiple APIs are available prefer:

1. Describe API
2. UI API
3. Tooling API
4. Metadata API
5. REST API
6. SOQL

Choose the lightest solution capable of solving the problem.

---

# Graph Engine

Everything in the application is represented as a graph.

Every metadata entity becomes a Node.

Examples:

* Object
* Field
* Apex Class
* Trigger
* Flow
* Validation Rule
* Permission Set
* Profile
* Dashboard
* Report
* LWC
* Aura Component
* Named Credential
* External Service
* Package

Relationships become Edges.

Examples:

* HAS_FIELD
* REFERENCES
* DEPENDS_ON
* CALLS
* EXECUTES
* LOOKUP_TO
* MASTER_DETAIL
* INVOKES
* BELONGS_TO
* USES_API

The Graph Service is the only component responsible for:

* Building nodes
* Building edges
* Relationship discovery
* Expansion
* Filtering
* Impact analysis

UI components must never construct graph relationships directly.

---

# UI Philosophy

The graph is the primary navigation experience.

Support:

* Expand
* Collapse
* Zoom
* Pan
* Mini-map
* Search
* Breadcrumbs
* Progressive loading
* Context menus
* Keyboard navigation
* Dark mode

Users should never lose context while navigating.

---

# Performance

Never load an entire org.

Always:

* Lazy load
* Cache aggressively
* Batch requests
* Paginate large datasets
* Avoid unnecessary Tooling API calls
* Avoid unnecessary Metadata API calls
* Minimize server round-trips

Performance is a first-class requirement.

---

# Security

Always respect:

* CRUD
* FLS
* Sharing
* User Mode
* Package Security Review expectations

Never expose unauthorized metadata.

Never bypass security without explicit justification.

Document any elevated access requirements.

---

# Coding Standards

Every Apex class should include:

* Documentation
* Meaningful naming
* Error handling
* Logging
* Unit tests

Every LWC should include:

* HTML
* JavaScript
* CSS
* Metadata XML

Avoid duplicated logic.

Avoid inline SOQL unless justified.

Bulkify everything.

Respect governor limits.

Prefer dependency injection where practical.

---

# Error Handling

Handle errors consistently.

Every service should:

* Throw meaningful exceptions
* Log failures
* Provide actionable messages
* Avoid leaking implementation details

Never silently swallow exceptions.

---

# Testing Standards

Every feature should include:

* Positive tests
* Negative tests
* Bulk tests
* Permission tests
* Boundary conditions
* Governor limit considerations

Aim for meaningful coverage rather than artificial coverage.

Tests should verify behavior, not implementation.

---

# Documentation Standards

Public classes should document:

* Purpose
* Responsibilities
* Dependencies
* Inputs
* Outputs
* Limitations

Complex algorithms should explain why the approach exists.

---

# AI Collaboration Rules

When generating code:

* Reuse existing code whenever possible.
* Do not rewrite unrelated files.
* Preserve coding style.
* Explain trade-offs.
* Highlight assumptions.
* Identify technical debt.
* Recommend future improvements.
* Prefer official Salesforce capabilities over custom frameworks.

If a better architectural option exists:

Explain why before implementing it.

---

# Deliverables

Whenever implementing a feature:

1. Explain the architecture.
2. Explain design decisions.
3. Identify risks.
4. Generate production-ready code.
5. Generate unit tests.
6. Explain deployment considerations.
7. Suggest future enhancements.

Every response should optimize for long-term maintainability.

---

# Success Criteria

Every contribution should move the project toward becoming:

* AppExchange Ready
* Enterprise Ready
* Secure
* Performant
* Modular
* Maintainable
* Extensible
* Well Tested
* Well Documented

Build software that experienced Salesforce architects would be comfortable deploying in production.
