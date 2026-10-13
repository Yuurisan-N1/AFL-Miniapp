<div align="center">

<img width="100%" alt="header" src="https://capsule-render.vercel.app/api?type=waving&height=210&text=AFL%20Miner%20Bot&fontAlign=50&fontAlignY=36&fontSize=56&desc=Mining%20Cycle%20%7C%20Account%20Tasks%20%7C%20Referral%20Rewards&descAlign=50&descAlignY=58"/>

<img alt="typing" src="https://readme-typing-svg.demolab.com?font=Inter&size=18&duration=3000&pause=650&center=true&vCenter=true&width=900&lines=Telegram+InitData+Sign+In;Reads+The+Mining+State+Of+Every+Account;Claims+The+Finished+Cycle+Then+Starts+The+Next+One;Claims+Every+Open+Account+Task;Invite+Bonus+%7C+Team+Commission;Multi+Account+%7C+Proxy+Support"/>

<p>
  <img alt="elixir" src="https://img.shields.io/badge/Elixir-1.14%2B-4B275F?logo=elixir&logoColor=white"/>
  <img alt="platform" src="https://img.shields.io/badge/Platform-AFL%20Miner-111111"/>
  <img alt="multi-account" src="https://img.shields.io/badge/Multi--Account-Supported-111111"/>
  <img alt="proxy" src="https://img.shields.io/badge/Proxy-Supported-111111"/>
  <img alt="author" src="https://img.shields.io/badge/by-Yuurisandesu-111111"/>
</p>

<p>
  <b>AFL Miner Bot</b> is a mining automation bot for the AFL Miner Telegram Miniapp.<br/>
  It signs in with the Telegram initData of each account and walks the whole account state: every open task is claimed, the invite bonus and the team commission are claimed whenever the server reports them ready, and the mining cycle is acted on a finished cycle is claimed first and the next one is started, an account that is not mining yet is started, and an account that is already mining is only reported so the cycle keeps moving.<br/>
  Built and distributed by <b>Yuurisandesu</b>.
</p>

</div>

---

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Running the Bot](#running-the-bot)
- [Features](#features)
- [File Structure](#file-structure)
- [Disclaimer](#disclaimer)

---

## Requirements

- Elixir `1.14+` with Erlang/OTP `25+`
- Git

---

## Installation

### Install Elixir

Elixir runs on the Erlang virtual machine, so **Erlang/OTP is required** Elixir cannot run without
it. Every package manager below installs Erlang/OTP for you as a dependency. The only path that needs
a separate Erlang step is the Windows manual installer (see below).

**Windows:**

*Option A package manager (recommended, installs Erlang automatically):*

```cmd
winget install Elixir.Elixir
```

*Option B manual installer (two installers, in this order):*

1. Download and run the **Erlang/OTP installer** from https://www.erlang.org/downloads
2. Run `erl -s halt` to check which OTP version you got
3. Download the **Elixir installer built for that exact OTP** from https://elixir-lang.org/install.html (`elixir-otp-<N>.exe`) and run it

Then open Command Prompt and verify:

```cmd
elixir --version
```

The output prints both versions, for example `Elixir 1.14.0 (compiled with Erlang/OTP 25)`.

**Linux (Ubuntu / Debian):**

```bash
sudo apt-get update
sudo apt-get install -y elixir
elixir --version
```

**macOS:**

```bash
brew install elixir
elixir --version
```

> If you do not have Homebrew, install it first from https://brew.sh

**Termux (Android):**

```bash
pkg update && pkg upgrade -y
pkg install elixir -y
elixir --version
```

> If the `elixir` package is not available in your Termux repository, install an Ubuntu environment first with `pkg install proot-distro`, then `proot-distro install ubuntu`, then `proot-distro login ubuntu` and run the Linux command above inside it.

---

### Clone and Install

**Clone the repository:**

```bash
git clone https://github.com/Yuurisan-N1/AFL-Miniapp.git
cd AFL-Miniapp
```

**Install dependencies:**

This bot uses only the Elixir standard library, so there is nothing to install. Erlang/OTP was already installed by the step above.

---

## Configuration

### 1. Accounts (data.txt)

Fill `data.txt` with the Telegram WebApp `initData` of each account, one per line:

```
query_id=AAH...&user=%7B%22id%22%3A123%7D&auth_date=...&hash=abc123
query_id=AAH...&user=%7B%22id%22%3A456%7D&auth_date=...&hash=def456
```

### 2. Proxy (proxy.txt)

Fill `proxy.txt` with proxies, one per line (optional, leave empty to run without proxy):

```
host:port
host:port:user:pass
http://user:pass@host:port
```

Proxies are assigned to accounts by index in round-robin order, and proxy credentials are masked in the log output.

### 3. Bot Settings (config.json)

`sleep_seconds` controls how long the bot waits between cycles. Accounts are processed back to back with no delay in between.

```json
{
  "settings": {
    "sleep_seconds": 3600
  }
}
```

---

## Running the Bot

**Linux / macOS:**

```bash
elixir --erl "+Bd" bot.exs
```

**Windows:**

```cmd
elixir --erl "+Bc" bot.exs
```

Or just double click `run_pc.bat`, which runs the Windows command above.

---

## Features

### Account State
At the start of every account the bot signs in with that account `initData` and logs the account name together with the current AFL balance. An account whose `initData` is refused is reported and skipped before any other request is sent.

### Account Tasks
Every task the server still reports as open is claimed in order and the reward the server credits is logged with the task name. A task that is already completed, a task that still needs a manual channel join and a task the server refuses are each reported as their own line, and the account keeps walking the rest of the list.

### Referral Rewards
The invite bonus and the team commission are claimed only when the account state reports them as ready, and the amount the server credits is logged for each one. An account with nothing pending is left alone, so the log stays readable.

### Mining Cycle
The mining state the server publishes for the account is read first. An account that is already mining is reported with the time it has left and the cycle moves on. When the accrual has finished the claim is sent and the amount credited is logged, then the next mining cycle is started on the same account. A start that the server refuses because the account has no linked TON wallet is reported and skipped.

### Multi Account
All accounts in `data.txt` are processed sequentially within every cycle. Each account block starts with its own proxy line, and blocks are separated by one blank line so the mapping between an account and its egress is auditable in the log. The cycle number is logged at the start of each round.

### Proxy Support
Proxies are loaded from `proxy.txt` and assigned to accounts by position in round-robin order. Proxy credentials are masked in log output. Running without proxies is fully supported.

### Auto Countdown
After all accounts complete a cycle, the bot displays a live `HH:MM:SS` countdown until the next cycle starts. A mining cycle that is still running is reported as a single line instead, so it never stalls the rest of the cycle.

---

## File Structure

```text
AFL-Miniapp/
├── bot.exs         # Main bot, full daily cycle automation
├── config.json     # Sleep duration between cycles
├── data.txt        # Account initData, one per line
├── proxy.txt       # Proxy list, one per line (optional)
├── run_pc.bat      # Launcher for Windows
├── LICENSE         # License file
└── utils/
    ├── banner.ex   # Banner display on startup
    └── json.ex     # JSON encoder and decoder
```

---

## Disclaimer

This tool is built for educational and technical exploration purposes. Use it wisely and at your own responsibility.

---

<div align="center">
<img width="100%" alt="footer" src="https://capsule-render.vercel.app/api?type=waving&height=120&section=footer"/>
</div>