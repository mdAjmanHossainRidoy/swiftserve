# SwiftServe: University Canteen Automation System

A production-grade, real-time cross-platform university canteen automation system built with Flutter and Supabase (PostgreSQL). Designed to eliminate long queues, secure financial transactions, and provide strict role-based access control (RBAC).


## Key Architectural Features

4-Tier Role-Based Access Control (RBAC):** Distinct interfaces and permission boundaries for Students, Admins (Cashiers), Kitchen Staff, and Counter Staff.
*Atomic Digital Wallet & Ledger: Secure top-ups, cash withdrawals/refunds, and automated checks preventing negative balances and race conditions.
*Finite State Machine (FSM) Order Lifecycle: Tracks orders strictly through `Pending` ➔ `Preparing` ➔ `Ready` ➔ `Completed` or `Cancelled`.
*Dynamic QR Order Verification: Time-based token generation (TOTP-style) combined with database-level Compare-And-Swap (CAS) to prevent Time-of-Check to Time-of-Use (TOCTOU) race conditions and double-delivery fraud.
*Real-Time WebSocket Synchronization: Live inventory updates and kitchen queues powered by Supabase Realtime streams.

---

## Tech Stack

*Frontend: Flutter (Dart), Mobile Scanner, Image Picker, Material Design dark-mode UI.
*Backend & Database: Supabase (PostgreSQL 3NF Relational Schema, PL/pgSQL Stored Procedures, Row Level Security, Supabase Storage for menu images).
*Version Control: Git & GitHub.

---

##  Project Structure

lib:

─ adminSection/          # Cashier wallet management & inventory control
─ userRoutingPages/      # Student home, cart, digital wallet, and order tracking
─ kitchenCounterscanner/ # Kitchen KDS queue & Counter QR scanner verification
─ app_router.dart        # Centralized named route definitions