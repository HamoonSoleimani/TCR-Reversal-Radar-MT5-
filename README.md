# 📡 TCR Reversal Radar (MT5)
<img width="744" height="812" alt="image" src="https://github.com/user-attachments/assets/8876aa9f-f53d-4c8b-9473-bffe14a257e6" />

> **Multi-Timeframe Trend Cascade & Reversal Engine for MetaTrader 5**  
> Tracks top-down trend health, pinpoints trend weakening, and fires high-probability turning points using multi-factor confluence scoring.

---

## ✨ Features

- 🪜 **Multi-Timeframe Ladder:** Monitors up to 8 custom timeframes alongside your chart timeframe.
- 📉 **Weakening Detection:** Detects trend fatigue *before* the turn via ADX decay, MACD fading, EMA squeeze, and structure breaks.
- 🎯 **Dual Signal Engine:**
  - `REV` 🔄 Reversals against higher-timeframe bias (major market turns).
  - `TURN` 🚀 Pullback completions in direction of HTF bias (trend re-entries).
- 💯 **0–100 Confluence Score:** Built from 8 weighted factors (Context, Weakening, Exhaustion, Divergence, CHoCH, Cascade Flip, Candle Triggers, Level Sweeps).
- 🎚️ **Strictness Levels (1–10):** Dynamic presets from relaxed scalping (1–3) to institutional filtering (8–10), plus fully manual mode (0).
- 🚫 **Zero Repaint:** Evaluates closed bars by default (`TIMING_CLOSE`). Intrabar live mode (`TIMING_LIVE`) available for scalpers.
- 🔔 **Multi-Channel Alerts:** Popup, Mobile Push Notifications, Email, and Audio alerts.

---

## 📊 How It Works

1. **Top-Down Trend State:** Every timeframe gets a directional trend state, momentum rating, and weakening score (0–100).
2. **Cascade "Front" Marker (`◄`):** Highlights the exact timeframe where the trend begins deteriorating from the bottom up.
3. **Confluence Filter:** Calculates a 0–100 score and validates independent confirmation gates.
4. **Execution:** Prints arrows, score labels, and dynamic invalidation / take-profit levels (`Entry`, `INV`, `T1 1.5R`, `T2 3R`).

---

## 🖥️ Interactive Dashboard

Click directly on your chart to control the engine in real time:

- **`[-]` / `[+]`** 🎛️ Adjust Strictness (1–10) instantly.
- **`[ ALL ]`** 🔀 Toggle signal filter (`ALL` ➔ `REV` ➔ `TURN`).
- **`[ CLOSE ]`** ⏱️ Switch between Bar-Close and Live intrabar mode.
- **`[-]` (Top Right)** 📦 Collapse/expand the dashboard to save chart space.

---

## 🤖 EA & iCustom Buffers

Easily connect to an Expert Advisor using `iCustom()`:

| Buffer | Name | Description |
|:---:|:---|:---|
| **0** | `BufBuy` | Buy arrow price level |
| **1** | `BufBuyC` | Buy grade (`0` = Low, `1` = Mid, `2` = High) |
| **2** | `BufSell` | Sell arrow price level |
| **3** | `BufSellC` | Sell grade (`0` = Low, `1` = Mid, `2` = High) |
| **4** | `BufBase` | Trend bias line (Slow EMA) |
| **5** | `BufBaseC` | Bias line color index (`0`–`4`) |
| **6** | `BufWarn` | Early-warning watch dot price |
| **7** | `BufWarnC` | Watch color (`0` = Bullish, `1` = Bearish) |
| **8** | `BufBuyScore` | Real-time Buy confluence score (`0`–`100`) |
| **9** | `BufSellScore`| Real-time Sell confluence score (`0`–`100`) |
| **10**| `BufBias` | Higher-TF directional bias (`-100` to `+100`) |

---

## 🚀 Quick Install

1. Download **`TCR_ReversalRadar.mq5`**.
2. In MT5, open **File** ➔ **Open Data Folder** ➔ navigate to `MQL5/Indicators/`.
3. Drop the file inside and press **Compile (`F7`)** in MetaEditor (or restart MT5).
4. Drag the indicator from your **Navigator** window onto any chart! 📈

---

## 📄 License

Distributed under the **MIT License**. Free for personal and commercial trading systems.
