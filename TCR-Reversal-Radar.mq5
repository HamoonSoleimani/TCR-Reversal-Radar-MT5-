//+------------------------------------------------------------------+
//|                                            TCR_ReversalRadar.mq5 |
//|                  Trend Cascade & Reversal Radar  (MetaTrader 5)  |
//+------------------------------------------------------------------+
//|  HOW IT WORKS (top-down)                                         |
//|   1. Every timeframe of the ladder gets a trend state (EMA stack,|
//|      slope, market structure, DI/ADX, macro EMA) with hysteresis,|
//|      a strength, a fast momentum and a WEAKENING score (ADX fade,|
//|      MACD decay, EMA squeeze, price/momentum vs fast EMA,        |
//|      divergence, opposite structure break).                      |
//|   2. The dashboard lists them from the highest TF down, so you   |
//|      see where the trend is still strong and where it starts to  |
//|      weaken or flip ("front" marker).                            |
//|   3. For both directions a 0-100 confluence score is built from: |
//|      prior-trend context, weakening, exhaustion, divergence,     |
//|      structure break (CHoCH), lower-TF cascade, candle, level.   |
//|   4. A signal fires on the first bar where the score and every   |
//|      gate of the chosen Strictness level are satisfied.          |
//|      REV  = against the higher-TF bias (true reversal)           |
//|      TURN = with the higher-TF bias (pullback ended)             |
//|                                                                  |
//|  STRICTNESS 1 (relaxed) .. 10 (very strict); 0 = manual values.  |
//|  Change it from the dashboard (+ / -) or in the inputs.          |
//|                                                                  |
//|  Signals are evaluated on CLOSED bars by default: no repaint.    |
//|  "Live" timing evaluates the forming bar and may repaint.        |
//|                                                                  |
//|  BUFFERS (for iCustom / EAs)                                     |
//|   0 buy arrow price     1 buy grade (0..2)                       |
//|   2 sell arrow price    3 sell grade (0..2)                      |
//|   4 bias line (slow EMA) 5 bias color index (0..4)               |
//|   6 watch dot price     7 watch color (0 bull / 1 bear)          |
//|   8 buy score 0..100    9 sell score 0..100                      |
//|  10 higher-TF bias -100..100                                     |
//+------------------------------------------------------------------+
#property copyright   "TCR Reversal Radar"
#property version     "1.00"
#property description "Multi-timeframe trend cascade with weakening detection,"
#property description "confluence-scored reversal signals, bias line, alerts and interactive dashboard."
#property indicator_chart_window
#property indicator_buffers 11
#property indicator_plots   4

#property indicator_label1  "TCR Buy"
#property indicator_type1   DRAW_COLOR_ARROW
#property indicator_color1  C'120,220,170',C'38,190,120',C'0,235,120'
#property indicator_width1  2
#property indicator_label2  "TCR Sell"
#property indicator_type2   DRAW_COLOR_ARROW
#property indicator_color2  C'255,160,160',C'240,84,84',C'255,40,70'
#property indicator_width2  2
#property indicator_label3  "TCR Bias line"
#property indicator_type3   DRAW_COLOR_LINE
#property indicator_color3  C'0,200,120',C'255,176,46',C'130,140,155',C'255,128,64',C'235,70,80'
#property indicator_width3  2
#property indicator_label4  "TCR Watch"
#property indicator_type4   DRAW_COLOR_ARROW
#property indicator_color4  C'0,200,120',C'235,70,80'
#property indicator_width4  1

//--- enumerations --------------------------------------------------
enum ENUM_TF_SLOT
  {
   TFS_OFF = 0,          // Off
   TFS_M1  = PERIOD_M1,  // M1
   TFS_M2  = PERIOD_M2,  // M2
   TFS_M3  = PERIOD_M3,  // M3
   TFS_M5  = PERIOD_M5,  // M5
   TFS_M10 = PERIOD_M10, // M10
   TFS_M15 = PERIOD_M15, // M15
   TFS_M20 = PERIOD_M20, // M20
   TFS_M30 = PERIOD_M30, // M30
   TFS_H1  = PERIOD_H1,  // H1
   TFS_H2  = PERIOD_H2,  // H2
   TFS_H3  = PERIOD_H3,  // H3
   TFS_H4  = PERIOD_H4,  // H4
   TFS_H6  = PERIOD_H6,  // H6
   TFS_H8  = PERIOD_H8,  // H8
   TFS_H12 = PERIOD_H12, // H12
   TFS_D1  = PERIOD_D1,  // D1
   TFS_W1  = PERIOD_W1,  // W1
   TFS_MN1 = PERIOD_MN1  // MN1
  };

enum ENUM_SIG_CLASS
  {
   SC_ALL  = 0,          // All turning points (REV + TURN)
   SC_REV  = 1,          // Reversals only (against HTF bias / neutral HTF)
   SC_TURN = 2           // Turns with HTF bias only (pullback ends)
  };

enum ENUM_TIMING
  {
   TIMING_CLOSE = 0,     // On bar close (non-repainting)
   TIMING_LIVE  = 1      // Intrabar / live (may repaint)
  };

enum ENUM_THEME
  {
   THEME_DARK  = 0,      // Dark
   THEME_LIGHT = 1       // Light
  };

//--- inputs ---------------------------------------------------------
input group "=== Timeframe ladder (any order, Off = skip; chart TF is added automatically) ==="
input ENUM_TF_SLOT InpTF1 = TFS_M5;    // Slot 1
input ENUM_TF_SLOT InpTF2 = TFS_M15;   // Slot 2
input ENUM_TF_SLOT InpTF3 = TFS_M30;   // Slot 3
input ENUM_TF_SLOT InpTF4 = TFS_H1;    // Slot 4
input ENUM_TF_SLOT InpTF5 = TFS_H4;    // Slot 5
input ENUM_TF_SLOT InpTF6 = TFS_D1;    // Slot 6
input ENUM_TF_SLOT InpTF7 = TFS_W1;    // Slot 7
input ENUM_TF_SLOT InpTF8 = TFS_OFF;   // Slot 8
input double InpTFWeightSlope = 0.5;   // Weight growth per TF step (0 = equal weights)

input group "=== Signals & strictness ==="
input int    InpStrictLevel = 5;       // Strictness: 0 = manual thresholds, 1 = relaxed ... 10 = very strict
input ENUM_SIG_CLASS InpSigClass = SC_ALL; // Which signals to show
input ENUM_TIMING InpTiming = TIMING_CLOSE; // Signal timing
input int    InpHistoryBars = 1500;    // Chart bars to evaluate
input int    InpMaxBarsPerTF = 15000;  // Max bars loaded per timeframe

input group "=== Trend model (applied on every timeframe) ==="
input int    InpFastMA = 21;           // Fast EMA
input int    InpSlowMA = 55;           // Slow EMA
input int    InpBaseMA = 200;          // Base (macro) EMA
input int    InpADXPeriod = 14;        // ADX / DI period
input int    InpATRPeriod = 14;        // ATR period
input int    InpRSIPeriod = 14;        // RSI period
input int    InpMACDFast = 12;         // MACD fast
input int    InpMACDSlow = 26;         // MACD slow
input int    InpMACDSig = 9;           // MACD signal
input int    InpSwingLen = 5;          // Swing pivot length (left = right)
input int    InpSlopeBars = 8;         // Slope lookback (bars)
input double InpSlopeNorm = 0.12;      // Slope for full vote (ATR per bar)
input double InpTrendEnter = 0.30;     // Trend score needed to enter a trend
input double InpTrendExit = 0.10;      // Trend score below which trend is dropped
input double InpWStack = 0.30;         // Vote weight: EMA stack
input double InpWSlope = 0.15;         // Vote weight: EMA slope
input double InpWStruct = 0.25;        // Vote weight: market structure
input double InpWDI = 0.20;            // Vote weight: DI / ADX
input double InpWMacro = 0.10;         // Vote weight: base EMA side

input group "=== Weakening & exhaustion detection ==="
input int    InpMemBars = 30;          // Prior-trend memory (bars per TF)
input int    InpWeakLook = 10;         // Peak lookback for fade detection
input double InpWeakLow = 35.0;        // Weakening threshold (0-100)
input double InpWeakHigh = 60.0;       // Turning threshold (0-100)
input int    InpExhWin = 8;            // Exhaustion window (bars)
input int    InpDivWindow = 12;        // Divergence validity (bars)
input int    InpDivMaxGap = 60;        // Max bars between divergence pivots
input double InpDivMinRSI = 2.0;       // Min RSI difference for divergence

input group "=== Score weights (relative) ==="
input double InpSCtx = 15.0;           // Prior trend context
input double InpSWeak = 15.0;          // Prior trend weakening
input double InpSExh = 15.0;           // Exhaustion (RSI / stretch)
input double InpSDiv = 10.0;           // Divergence
input double InpSBreak = 15.0;         // Structure break (CHoCH)
input double InpSCascade = 15.0;       // Lower-TF cascade flip
input double InpSCandle = 10.0;        // Candle trigger
input double InpSLevel = 5.0;          // Level sweep / touch

input group "=== Manual thresholds (used only when Strictness = 0) ==="
input double InpMScore = 58.0;         // Min confluence score (0-100)
input int    InpMGroups = 3;           // Min confirmation groups (of 6)
input double InpMCtx = 0.20;           // Min prior-trend context (0-1)
input double InpMWeak = 0.23;          // Min prior-trend weakening (0-1)
input double InpMCascade = 0.23;       // Min lower-TF cascade flip (0-1)
input int    InpMDepth = 1;            // Min contiguous flipped TFs from the lowest
input double InpMOversold = 37.0;      // RSI level counted as exhaustion (sell side uses 100 - x)
input double InpMStretch = 1.6;        // Stretch from slow EMA counted as exhaustion (ATR)
input int    InpMCooldown = 9;         // Bars between same-side signals
input double InpMBreak = 0.0;          // Min structure-break (CHoCH) quality (0 = not required)
input int    InpMStructWin = 5;        // Structure-break validity (bars)
input double InpMMomMin = 12.5;        // Momentum needed to call a TF flipped (0-100)
input bool   InpMCandle = false;       // Require a confirming candle

input group "=== Chart display ==="
input bool   InpShowArrows = true;     // Show signal arrows
input bool   InpShowLabels = true;     // Show score labels
input bool   InpShowWatch = true;      // Show weakening-watch dots
input bool   InpShowBase = true;       // Show bias line (slow EMA colored by MTF bias)
input bool   InpShowLevels = true;     // Show invalidation / targets of last signal
input int    InpMaxLabels = 40;        // Max labels kept on chart
input double InpArrowOffset = 0.6;     // Arrow distance from bar (ATR)

input group "=== Dashboard ==="
input bool   InpShowDash = true;       // Show dashboard
input ENUM_BASE_CORNER InpDashCorner = CORNER_LEFT_UPPER; // Corner
input int    InpDashX = 8;             // X offset
input int    InpDashY = 18;            // Y offset
input int    InpDashFont = 9;          // Font size (layout scales with it)
input ENUM_THEME InpDashTheme = THEME_DARK; // Theme
input bool   InpDashLive = true;       // Dashboard uses forming bars (live)
input string InpFontName = "Segoe UI"; // Font

input group "=== Alerts ==="
input bool   InpAlertPopup = true;     // Popup alert
input bool   InpAlertPush = false;     // Push notification
input bool   InpAlertMail = false;     // E-mail
input string InpAlertSound = "";       // Sound file (empty = none)
input bool   InpAlertWatch = false;    // Also alert on weakening-watch

//--- constants / structs --------------------------------------------
#define MAX_TF 10

struct TFBar
  {
   datetime t;
   double   o, h, l, c;
   long     v;
   double   atr, emaF, emaS, emaB;
   double   sTR, sPDM, sMDM, pdi, mdi, adx;
   double   ag, al, rsi;
   double   emaMF, emaMS, macd, sig, hist;
   double   rsiMin, rsiMax, stDn, stUp;
   double   shP, slP;
   int      shI, slI, sh2I, sl2I;
   int      shBrk, slBrk;
   int      sdir;
   int      lastChUp, lastChDn, lastDivBull, lastDivBear;
   double   dscore;
   int      trend;
   double   tstr, mom, weak, memUp, memDn;
  };

struct SParams
  {
   double   minScore;
   int      minGroups;
   double   minCtx;
   double   minWeak;
   double   minCascade;
   int      minDepth;
   double   os;
   double   ob;
   double   stretch;
   int      cooldown;
   double   sbMin;
   bool     needCandle;
   int      structWin;
   double   momMin;
  };

struct SEval
  {
   double   score;
   double   ctx, wk, ex, dv, sb, cs, cd, lv;
   int      groups;
   int      depth;
   int      cls;
   bool     gates;
   bool     pass;
  };

struct STheme
  {
   color bg, header, border, text, dim, track, bull, bear, amber, orange, accent, btn, btnTxt;
  };

STheme   g_th;

//--- indicator buffers ------------------------------------------------
double BufBuy[];
double BufBuyC[];
double BufSell[];
double BufSellC[];
double BufBase[];
double BufBaseC[];
double BufWarn[];
double BufWarnC[];
double BufBuyScore[];
double BufSellScore[];
double BufBias[];

//--- simple globals ---------------------------------------------------
string   g_pfx = "TCR_";
string   G_UP = "^", G_DN = "v", G_RNG = "-";
ENUM_TIMEFRAMES g_tfs[MAX_TF];
int      g_cnt = 0;
int      g_cm = 0;
int      g_km[MAX_TF];
int      g_off = 0;
int      g_ratesTotal = 0;
int      g_chartSec = 60;
double   g_point = 0.00001;
bool     g_ready = false;
int      g_level = 5;
int      g_sigClass = 0;
bool     g_collapsed = false;
SParams  g_P;
int      g_lastEval = -1;
int      g_lastBuyK = -100000;
int      g_lastSellK = -100000;
int      g_lastWBuyK = -100000;
int      g_lastWSellK = -100000;
datetime g_lastAlertBar = 0;
int      g_lsDir = 0;
int      g_lsK = -1;
int      g_lsGrade = 0;
int      g_lsCls = 0;
double   g_lsScore = 0.0;
double   g_lsEntry = 0.0;
double   g_lsInv = 0.0;
SEval    g_dBull;
SEval    g_dBear;
double   g_dBias = 0.0;
double   g_dBiasWeak = 0.0;
string   g_lblNm[];
int      g_lblCnt = 0;

//--- engine / dashboard runtime globals --------------------------------
double   g_u = 1.0;
int      g_timing = 0;
bool     g_needFull = false;
bool     g_pBuy = false, g_pSell = false;
bool     g_wsBuy = false, g_wsSell = false;
int      g_sigDir = 0;
int      g_watchDir = 0;
double   g_sigScore = 0.0;
int      g_sigCls = 0;
int      g_sigGrade = 0;
datetime g_lsT = 0;
bool     g_lsDirty = false;
datetime g_lastWatchAlert = 0;
datetime g_lastTry[MAX_TF];
ulong    g_lastDash = 0;
int      g_rtLast = 0;
double   g_dAll = 0.0;
bool     g_dWatchBuy = false;
bool     g_dWatchSell = false;
SEval    g_eSig;

//+------------------------------------------------------------------+
//| helpers                                                          |
//+------------------------------------------------------------------+
double Clamp(const double x, const double lo, const double hi) { return (x < lo) ? lo : ((x > hi) ? hi : x); }
double Sgn(const double x)                                    { return (x > 0.0) ? 1.0 : ((x < 0.0) ? -1.0 : 0.0); }
double Lerp(const double a, const double b, const double t)   { return a + (b - a)*t; }
string Pick(const bool c, const string a, const string b)     { return c ? a : b; }

string TFName(const ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return "M1";
      case PERIOD_M2:  return "M2";
      case PERIOD_M3:  return "M3";
      case PERIOD_M4:  return "M4";
      case PERIOD_M5:  return "M5";
      case PERIOD_M6:  return "M6";
      case PERIOD_M10: return "M10";
      case PERIOD_M12: return "M12";
      case PERIOD_M15: return "M15";
      case PERIOD_M20: return "M20";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
      case PERIOD_H3:  return "H3";
      case PERIOD_H4:  return "H4";
      case PERIOD_H6:  return "H6";
      case PERIOD_H8:  return "H8";
      case PERIOD_H12: return "H12";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN";
     }
   return IntegerToString(PeriodSeconds(tf)/60) + "m";
  }

//+------------------------------------------------------------------+
//| One timeframe: bars + indicators + structure + trend state       |
//+------------------------------------------------------------------+
class CTFData
  {
public:
   ENUM_TIMEFRAMES tf;
   int      tfSec;
   int      n;
   int      warm;
   int      lastCount;
   bool     ready;
   bool     synced;
   bool     reloaded;
   TFBar    b[];

            CTFData(void)
     {
      tf = PERIOD_CURRENT; tfSec = 60; n = 0; warm = 120; lastCount = 0;
      ready = false; synced = false; reloaded = false;
     }
   void     Setup(const ENUM_TIMEFRAMES period, const int warmBars);
   bool     Load(const string sym, const int count);
   bool     Refresh(const string sym);
   void     Fill(const int i, const MqlRates &r);
   int      UpperIdx(const datetime x);
   int      MapClosed(const datetime T);
   void     ComputeFrom(const int from);
   double   EmaStep(const int i, const int period, const double prev);
   void     CalcIndicators(const int i);
   void     CalcStructure(const int i);
   void     CalcTrend(const int i);
  };

CTFData g_tf[MAX_TF];

void CTFData::Setup(const ENUM_TIMEFRAMES period, const int warmBars)
  {
   tf = period;
   tfSec = PeriodSeconds(period);
   if(tfSec <= 0) tfSec = 60;
   warm = warmBars;
   n = 0;
   ready = false;
  }

void CTFData::Fill(const int i, const MqlRates &r)
  {
   b[i].t = r.time;
   b[i].o = r.open;
   b[i].h = r.high;
   b[i].l = r.low;
   b[i].c = r.close;
   b[i].v = r.tick_volume;
  }

bool CTFData::Load(const string sym, const int count)
  {
   ready = false;
   n = 0;
   lastCount = count;
   MqlRates r[];
   ArraySetAsSeries(r, false);
   const int got = CopyRates(sym, tf, 0, count, r);
   if(got < warm + 30)
      return false;
   ArrayResize(b, got, 512);
   for(int i = 0; i < got; i++)
      Fill(i, r[i]);
   n = got;
   ComputeFrom(0);
   synced = (bool)SeriesInfoInteger(sym, tf, SERIES_SYNCHRONIZED);
   ready = true;
   reloaded = true;
   return true;
  }

bool CTFData::Refresh(const string sym)
  {
   if(!ready)
      return false;
   if(!synced && (bool)SeriesInfoInteger(sym, tf, SERIES_SYNCHRONIZED))
      return Load(sym, lastCount);
   const datetime lastT = iTime(sym, tf, 0);
   if(lastT == 0)
      return false;
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int from = n - 1;
   if(lastT == b[n-1].t)
     {
      if(CopyRates(sym, tf, 0, 1, r) != 1)
         return false;
      Fill(n - 1, r[0]);
     }
   else if(lastT > b[n-1].t)
     {
      const int got = CopyRates(sym, tf, b[n-1].t, lastT, r);
      if(got < 2 || r[0].time != b[n-1].t)
         return Load(sym, lastCount);
      ArrayResize(b, n + got - 1, 512);
      Fill(n - 1, r[0]);
      for(int q = 1; q < got; q++)
         Fill(n - 1 + q, r[q]);
      n += got - 1;
     }
   else
      return Load(sym, lastCount);
   ComputeFrom(from);
   return true;
  }

int CTFData::UpperIdx(const datetime x)
  {
   int lo = 0, hi = n - 1, res = -1;
   while(lo <= hi)
     {
      const int mid = (lo + hi) >> 1;
      if(b[mid].t <= x) { res = mid; lo = mid + 1; }
      else hi = mid - 1;
     }
   return res;
  }

//--- last bar that is fully closed at time T (no look-ahead) ----------
int CTFData::MapClosed(const datetime T)
  {
   if(n <= 0)
      return -1;
   const int k1 = UpperIdx(T - tfSec);
   const int k2 = UpperIdx(T) - 1;
   const int k = MathMax(k1, k2);
   return (k >= warm) ? k : -1;
  }

void CTFData::ComputeFrom(const int from)
  {
   for(int i = MathMax(from, 0); i < n; i++)
     {
      CalcIndicators(i);
      CalcStructure(i);
      CalcTrend(i);
     }
  }

double CTFData::EmaStep(const int i, const int period, const double prev)
  {
   if(i < period - 1)
      return b[i].c;
   if(i == period - 1)
     {
      double s = 0.0;
      for(int q = 0; q < period; q++)
         s += b[q].c;
      return s/period;
     }
   return prev + (2.0/(period + 1.0))*(b[i].c - prev);
  }

void CTFData::CalcIndicators(const int i)
  {
   const double c = b[i].c, h = b[i].h, l = b[i].l;
   const double pc = (i > 0) ? b[i-1].c : b[i].o;
   const double ph = (i > 0) ? b[i-1].h : h;
   const double pl = (i > 0) ? b[i-1].l : l;
   const double tr = MathMax(h - l, MathMax(MathAbs(h - pc), MathAbs(l - pc)));
   const double ka = 1.0/MathMax(InpATRPeriod, 1);
   const double kd = 1.0/MathMax(InpADXPeriod, 1);
   const double kr = 1.0/MathMax(InpRSIPeriod, 1);
   const double up = h - ph, dn = pl - l;
   const double pdm = (up > dn && up > 0.0) ? up : 0.0;
   const double mdm = (dn > up && dn > 0.0) ? dn : 0.0;
   if(i == 0)
     {
      b[i].atr = tr; b[i].sTR = tr; b[i].sPDM = 0.0; b[i].sMDM = 0.0;
      b[i].adx = 0.0; b[i].ag = 0.0; b[i].al = 0.0;
     }
   else
     {
      b[i].atr  = b[i-1].atr  + (tr  - b[i-1].atr )*ka;
      b[i].sTR  = b[i-1].sTR  + (tr  - b[i-1].sTR )*kd;
      b[i].sPDM = b[i-1].sPDM + (pdm - b[i-1].sPDM)*kd;
      b[i].sMDM = b[i-1].sMDM + (mdm - b[i-1].sMDM)*kd;
      b[i].ag   = b[i-1].ag   + (MathMax(c - pc, 0.0) - b[i-1].ag)*kr;
      b[i].al   = b[i-1].al   + (MathMax(pc - c, 0.0) - b[i-1].al)*kr;
     }
   b[i].pdi = (b[i].sTR > 0.0) ? 100.0*b[i].sPDM/b[i].sTR : 0.0;
   b[i].mdi = (b[i].sTR > 0.0) ? 100.0*b[i].sMDM/b[i].sTR : 0.0;
   const double dsum = b[i].pdi + b[i].mdi;
   const double dx = (dsum > 0.0) ? 100.0*MathAbs(b[i].pdi - b[i].mdi)/dsum : 0.0;
   if(i > 0)
      b[i].adx = b[i-1].adx + (dx - b[i-1].adx)*kd;
   if(b[i].al <= 1e-12)
      b[i].rsi = (b[i].ag <= 1e-12) ? 50.0 : 100.0;
   else
      b[i].rsi = 100.0 - 100.0/(1.0 + b[i].ag/b[i].al);
   //--- EMAs and MACD
   b[i].emaF  = EmaStep(i, InpFastMA,  (i > 0) ? b[i-1].emaF  : c);
   b[i].emaS  = EmaStep(i, InpSlowMA,  (i > 0) ? b[i-1].emaS  : c);
   b[i].emaB  = EmaStep(i, InpBaseMA,  (i > 0) ? b[i-1].emaB  : c);
   b[i].emaMF = EmaStep(i, InpMACDFast, (i > 0) ? b[i-1].emaMF : c);
   b[i].emaMS = EmaStep(i, InpMACDSlow, (i > 0) ? b[i-1].emaMS : c);
   b[i].macd  = b[i].emaMF - b[i].emaMS;
   if(i == 0)
      b[i].sig = b[i].macd;
   else
      b[i].sig = b[i-1].sig + (b[i].macd - b[i-1].sig)*(2.0/(MathMax(InpMACDSig, 1) + 1.0));
   b[i].hist = b[i].macd - b[i].sig;
   //--- rolling exhaustion features (strictness independent)
   const int W = MathMax(InpExhWin, 2);
   double rmin = 100.0, rmax = 0.0, sd = -1000.0, su = -1000.0;
   for(int q = MathMax(i - W + 1, 0); q <= i; q++)
     {
      rmin = MathMin(rmin, b[q].rsi);
      rmax = MathMax(rmax, b[q].rsi);
      const double aq = MathMax(b[q].atr, g_point);
      sd = MathMax(sd, (b[q].emaS - b[q].l)/aq);
      su = MathMax(su, (b[q].h - b[q].emaS)/aq);
     }
   b[i].rsiMin = rmin;
   b[i].rsiMax = rmax;
   b[i].stDn = sd;
   b[i].stUp = su;
  }

//--- swing pivots, BOS / CHoCH, RSI divergence -------------------------
void CTFData::CalcStructure(const int i)
  {
   if(i == 0)
     {
      b[i].shP = 0.0; b[i].slP = 0.0;
      b[i].shI = -1; b[i].slI = -1; b[i].sh2I = -1; b[i].sl2I = -1;
      b[i].shBrk = 1; b[i].slBrk = 1; b[i].sdir = 0;
      b[i].lastChUp = -1; b[i].lastChDn = -1;
      b[i].lastDivBull = -1; b[i].lastDivBear = -1;
      return;
     }
   b[i].shP = b[i-1].shP;  b[i].slP = b[i-1].slP;
   b[i].shI = b[i-1].shI;  b[i].slI = b[i-1].slI;
   b[i].sh2I = b[i-1].sh2I; b[i].sl2I = b[i-1].sl2I;
   b[i].shBrk = b[i-1].shBrk; b[i].slBrk = b[i-1].slBrk;
   b[i].sdir = b[i-1].sdir;
   b[i].lastChUp = b[i-1].lastChUp;   b[i].lastChDn = b[i-1].lastChDn;
   b[i].lastDivBull = b[i-1].lastDivBull; b[i].lastDivBear = b[i-1].lastDivBear;

   const int L = MathMax(InpSwingLen, 2);
   const int p = i - L;
   if(p - L >= 0)
     {
      bool isH = true, isL = true;
      const double hp = b[p].h, lp = b[p].l;
      for(int k = p - L; k < p; k++)
        {
         if(b[k].h > hp) isH = false;
         if(b[k].l < lp) isL = false;
        }
      for(int k = p + 1; k <= p + L; k++)
        {
         if(b[k].h >= hp) isH = false;
         if(b[k].l <= lp) isL = false;
        }
      if(isH)
        {
         const int q = b[i].shI;
         if(q >= 0 && p - q >= 4 && p - q <= InpDivMaxGap && hp > b[q].h &&
            b[p].rsi < b[q].rsi - InpDivMinRSI && b[q].rsi >= 50.0)
            b[i].lastDivBear = i;
         b[i].sh2I = q; b[i].shI = p; b[i].shP = hp; b[i].shBrk = 0;
        }
      if(isL)
        {
         const int q = b[i].slI;
         if(q >= 0 && p - q >= 4 && p - q <= InpDivMaxGap && lp < b[q].l &&
            b[p].rsi > b[q].rsi + InpDivMinRSI && b[q].rsi <= 50.0)
            b[i].lastDivBull = i;
         b[i].sl2I = q; b[i].slI = p; b[i].slP = lp; b[i].slBrk = 0;
        }
     }
   const double cl = b[i].c;
   if(b[i].shI >= 0 && b[i].shBrk == 0 && cl > b[i].shP)
     {
      b[i].shBrk = 1;
      if(b[i].sdir == -1) b[i].lastChUp = i;
      b[i].sdir = 1;
     }
   else if(b[i].slI >= 0 && b[i].slBrk == 0 && cl < b[i].slP)
     {
      b[i].slBrk = 1;
      if(b[i].sdir == 1) b[i].lastChDn = i;
      b[i].sdir = -1;
     }
  }

//--- trend direction / strength / momentum / weakening ------------------
void CTFData::CalcTrend(const int i)
  {
   const double A = MathMax(b[i].atr, g_point);
   const int sb = MathMax(InpSlopeBars, 1);
   const double vStack = 0.5*Sgn(b[i].emaF - b[i].emaS) + 0.3*Sgn(b[i].c - b[i].emaS) + 0.2*Sgn(b[i].c - b[i].emaF);
   double vSlope = 0.0;
   if(i - sb >= 0)
      vSlope = Clamp(((b[i].emaS - b[i-sb].emaS)/(A*sb))/MathMax(InpSlopeNorm, 0.001), -1.0, 1.0);
   const double vStruct = (double)b[i].sdir;
   const double dsum = b[i].pdi + b[i].mdi;
   const double vDI = (dsum > 0.0) ? ((b[i].pdi - b[i].mdi)/dsum)*Clamp(b[i].adx/25.0, 0.0, 1.0) : 0.0;
   const double vMacro = (i >= InpBaseMA - 1) ? Sgn(b[i].c - b[i].emaB) : 0.0;
   const double wsum = MathMax(InpWStack + InpWSlope + InpWStruct + InpWDI + InpWMacro, 0.0001);
   const double D = (InpWStack*vStack + InpWSlope*vSlope + InpWStruct*vStruct + InpWDI*vDI + InpWMacro*vMacro)/wsum;
   b[i].dscore = D;
   const int prevT = (i > 0) ? b[i-1].trend : 0;
   int tr = 0;
   if(D >= InpTrendEnter) tr = 1;
   else if(D <= -InpTrendEnter) tr = -1;
   else if(prevT == 1 && D > InpTrendExit) tr = 1;
   else if(prevT == -1 && D < -InpTrendExit) tr = -1;
   b[i].trend = (i >= warm) ? tr : 0;

   //--- strength 0..100
   const double sA = Clamp((b[i].adx - 12.0)/28.0, 0.0, 1.0);
   const double sB = MathAbs(D);
   const double sC = Clamp(MathAbs(b[i].emaF - b[i].emaS)/(A*1.5), 0.0, 1.0);
   b[i].tstr = 100.0*(0.40*sA + 0.35*sB + 0.25*sC);

   //--- fast momentum -100..100
   const double m1 = Clamp(b[i].hist/(0.15*A), -1.0, 1.0);
   const double m2 = Clamp((b[i].rsi - 50.0)/25.0, -1.0, 1.0);
   const int i3 = MathMax(i - 3, 0);
   const double m3 = Clamp((b[i].emaF - b[i3].emaF)/(A*0.3), -1.0, 1.0);
   b[i].mom = 100.0*(0.4*m1 + 0.3*m2 + 0.3*m3);

   //--- weakening of the current trend 0..100
   double wk = 0.0;
   const int t = b[i].trend;
   if(t != 0)
     {
      const int j0 = MathMax(i - MathMax(InpWeakLook, 2), 0);
      double adxPk = 0.0, histPk = 0.0, gapPk = 0.0;
      for(int j = j0; j <= i; j++)
        {
         adxPk  = MathMax(adxPk, b[j].adx);
         histPk = MathMax(histPk, t*b[j].hist);
         gapPk  = MathMax(gapPk, t*(b[j].emaF - b[j].emaS));
        }
      double w1 = 0.0, w2 = 0.0, w3 = 0.0, w4 = 0.0;
      if(adxPk >= 18.0)
         w1 = Clamp((adxPk - b[i].adx)/(adxPk*0.30), 0.0, 1.0);
      if(histPk > 0.0)
         w2 = Clamp((0.8 - (t*b[i].hist)/histPk)/0.8, 0.0, 1.0);
      if(gapPk > 0.0)
         w3 = Clamp(1.0 - (t*(b[i].emaF - b[i].emaS))/gapPk, 0.0, 1.0);
      if(t*(b[i].c - b[i].emaF) < 0.0) w4 += 0.6;
      if(t*b[i].mom < 0.0)             w4 += 0.4;
      const int ld = (t == 1) ? b[i].lastDivBear : b[i].lastDivBull;
      const double w5 = (ld >= 0 && i - ld <= InpDivWindow) ? 1.0 : 0.0;
      const double w6 = (b[i].sdir == -t) ? 1.0 : 0.0;
      wk = 100.0*(0.20*w1 + 0.20*w2 + 0.15*w3 + 0.15*MathMin(w4, 1.0) + 0.10*w5 + 0.20*w6);
     }
   b[i].weak = wk;

   //--- memory of recent trend strength per direction
   double mu = 0.0, md = 0.0;
   for(int j = MathMax(i - MathMax(InpMemBars, 2) + 1, 0); j <= i; j++)
     {
      if(b[j].trend == 1)       mu = MathMax(mu, b[j].tstr);
      else if(b[j].trend == -1) md = MathMax(md, b[j].tstr);
     }
   b[i].memUp = mu;
   b[i].memDn = md;
  }

//+------------------------------------------------------------------+
//| Strictness level -> parameter set                                |
//+------------------------------------------------------------------+
void BuildParams()
  {
   if(g_level <= 0)
     {
      g_P.minScore   = InpMScore;
      g_P.minGroups  = InpMGroups;
      g_P.minCtx     = InpMCtx;
      g_P.minWeak    = InpMWeak;
      g_P.minCascade = InpMCascade;
      g_P.minDepth   = InpMDepth;
      g_P.os         = InpMOversold;
      g_P.ob         = 100.0 - InpMOversold;
      g_P.stretch    = MathMax(InpMStretch, 0.2);
      g_P.cooldown   = MathMax(InpMCooldown, 0);
      g_P.sbMin      = InpMBreak;
      g_P.needCandle = InpMCandle;
      g_P.structWin  = MathMax(InpMStructWin, 1);
      g_P.momMin     = InpMMomMin;
      return;
     }
   const double t = Clamp((g_level - 1)/9.0, 0.0, 1.0);
   g_P.minScore   = 40.0 + 34.0*(1.0 - MathPow(1.0 - t, 1.35));
   g_P.minGroups  = (int)MathRound(Lerp(1.0, 5.0, t));
   g_P.minCtx     = Lerp(0.05, 0.40, t);
   g_P.minWeak    = Lerp(0.05, 0.45, t);
   g_P.minCascade = Lerp(0.05, 0.45, t);
   g_P.minDepth   = (int)MathFloor(t*3.2);
   g_P.os         = Lerp(45.0, 28.0, t);
   g_P.ob         = 100.0 - g_P.os;
   g_P.stretch    = Lerp(1.0, 2.4, t);
   g_P.cooldown   = (int)MathRound(Lerp(3.0, 16.0, t));
   g_P.sbMin      = (g_level <= 5) ? 0.0 : 0.75*(g_level - 5)/5.0;
   g_P.needCandle = (g_level >= 9);
   g_P.structWin  = (int)MathRound(Lerp(6.0, 3.0, t));
   g_P.momMin     = Lerp(5.0, 22.0, t);
  }

//+------------------------------------------------------------------+
//| Timeframe ladder (ascending); chart TF is always included        |
//+------------------------------------------------------------------+
void BuildLadder()
  {
   ENUM_TIMEFRAMES tmp[MAX_TF];
   ENUM_TF_SLOT    sl[8];
   int n = 0;
   tmp[n++] = (ENUM_TIMEFRAMES)_Period;
   sl[0] = InpTF1; sl[1] = InpTF2; sl[2] = InpTF3; sl[3] = InpTF4;
   sl[4] = InpTF5; sl[5] = InpTF6; sl[6] = InpTF7; sl[7] = InpTF8;
   for(int i = 0; i < 8; i++)
     {
      if(sl[i] == TFS_OFF)
         continue;
      const ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)sl[i];
      if(PeriodSeconds(tf) <= 0)
         continue;
      bool dup = false;
      for(int j = 0; j < n; j++)
         if(tmp[j] == tf)
           {
            dup = true;
            break;
           }
      if(!dup && n < MAX_TF)
         tmp[n++] = tf;
     }
   for(int i = 1; i < n; i++)
     {
      const ENUM_TIMEFRAMES x = tmp[i];
      int j = i - 1;
      while(j >= 0 && PeriodSeconds(tmp[j]) > PeriodSeconds(x))
        {
         tmp[j + 1] = tmp[j];
         j--;
        }
      tmp[j + 1] = x;
     }
   g_cnt = n;
   g_cm = 0;
   for(int i = 0; i < n; i++)
     {
      g_tfs[i] = tmp[i];
      if(tmp[i] == (ENUM_TIMEFRAMES)_Period)
         g_cm = i;
     }
  }

void InitTFData()
  {
   const int warm = MathMax(InpBaseMA, MathMax(InpSlowMA*3, 120)) + 10;
   for(int s = 0; s < MAX_TF; s++)
     {
      g_km[s] = -1;
      g_lastTry[s] = 0;
     }
   for(int s = 0; s < g_cnt; s++)
      g_tf[s].Setup(g_tfs[s], warm);
  }

//--- how many bars a timeframe must hold to cover the evaluated range
int BarsNeeded(const int s)
  {
   const double ratio = (double)InpHistoryBars*(double)g_chartSec/(double)MathMax(g_tf[s].tfSec, 1);
   int need = (int)MathCeil(ratio) + g_tf[s].warm + 120;
   need = MathMax(need, g_tf[s].warm + 200);
   const int cap = MathMax(InpMaxBarsPerTF, g_tf[s].warm + 200);
   return MathMin(need, cap);
  }

//--- load / refresh all timeframes; returns true when something was (re)loaded
bool SyncData()
  {
   bool any = false;
   const datetime now = TimeLocal();
   for(int s = 0; s < g_cnt; s++)
     {
      if(!g_tf[s].ready)
        {
         if(g_lastTry[s] != 0 && now - g_lastTry[s] < 2)
            continue;
         g_lastTry[s] = now;
         if(g_tf[s].Load(_Symbol, BarsNeeded(s)))
            any = true;
         g_tf[s].reloaded = false;
         continue;
        }
      g_tf[s].Refresh(_Symbol);
      if(g_tf[s].reloaded)
        {
         any = true;
         g_tf[s].reloaded = false;
        }
     }
   if(any)
      g_needFull = true;
   return any;
  }

//--- map one chart bar (open time T) to the matching bar of every timeframe
void MapAll(const datetime T, const bool live)
  {
   for(int s = 0; s < g_cnt; s++)
     {
      g_km[s] = -1;
      if(!g_tf[s].ready || g_tf[s].n <= 0)
         continue;
      int k;
      if(live)
         k = g_tf[s].n - 1;
      else
         if(s == g_cm)
            k = g_tf[s].UpperIdx(T);
         else
            if(g_tf[s].tfSec < g_chartSec)
               k = g_tf[s].MapClosed(T + g_chartSec);
            else
               k = g_tf[s].MapClosed(T);
      g_km[s] = (k >= g_tf[s].warm) ? k : -1;
     }
  }

//+------------------------------------------------------------------+
//| Scoring helpers                                                  |
//+------------------------------------------------------------------+
bool ClassOK(const int cls)
  {
   if(g_sigClass == (int)SC_REV)
      return (cls == 1);
   if(g_sigClass == (int)SC_TURN)
      return (cls == 2);
   return true;
  }

//--- how far a timeframe has turned toward direction d (0..1)
double FlipScore(const TFBar &x, const int d)
  {
   const double A = MathMax(x.atr, g_point);
   const double f = Clamp(d*x.mom/45.0, 0.0, 1.0);
   const double g = Clamp((d*(x.c - x.emaF)/A + 0.2)/0.8, 0.0, 1.0);
   const double s = (x.sdir == d) ? 1.0 : 0.0;
   return 0.45*f + 0.25*g + 0.30*s;
  }

bool Flipped(const TFBar &x, const int d)
  {
   return (d*x.mom >= g_P.momMin) && (d*(x.c - x.emaF) > 0.0);
  }

//--- exhaustion of the prior move: RSI extreme + stretch from slow EMA
double ExhScore(const TFBar &x, const int d)
  {
   double rsiPart, strPart;
   if(d == 1)
     {
      rsiPart = Clamp((g_P.os + 12.0 - x.rsiMin)/20.0, 0.0, 1.0);
      strPart = Clamp(x.stDn/g_P.stretch, 0.0, 1.0);
     }
   else
     {
      rsiPart = Clamp((x.rsiMax - (g_P.ob - 12.0))/20.0, 0.0, 1.0);
      strPart = Clamp(x.stUp/g_P.stretch, 0.0, 1.0);
     }
   return 0.5*rsiPart + 0.5*strPart;
  }

double DivScore(const TFBar &x, const int k, const int d)
  {
   const int ld = (d == 1) ? x.lastDivBull : x.lastDivBear;
   if(ld < 0)
      return 0.0;
   const int age = k - ld;
   if(age < 0 || age > InpDivWindow)
      return 0.0;
   return 1.0 - 0.5*(double)age/(double)MathMax(InpDivWindow, 1);
  }

double BreakScore(const TFBar &x, const int k, const int d)
  {
   const int lc = (d == 1) ? x.lastChUp : x.lastChDn;
   if(lc < 0)
      return 0.0;
   const int age = k - lc;
   const int W = MathMax(g_P.structWin, 1);
   if(age < 0 || age > W)
      return 0.0;
   return 1.0 - 0.5*(double)age/(double)W;
  }

//--- trigger candle on the chart timeframe
double CandleScore(const int d)
  {
   const int cm = g_cm;
   const int k = g_km[cm];
   if(k < 2)
      return 0.0;
   const double o = g_tf[cm].b[k].o, h = g_tf[cm].b[k].h, l = g_tf[cm].b[k].l, c = g_tf[cm].b[k].c;
   const double po = g_tf[cm].b[k-1].o, pc = g_tf[cm].b[k-1].c, ph = g_tf[cm].b[k-1].h, pl = g_tf[cm].b[k-1].l;
   const double A = MathMax(g_tf[cm].b[k].atr, g_point);
   const double rng = h - l;
   if(rng <= 0.0)
      return 0.0;
   const double body = MathAbs(c - o);
   const bool dirBar = (d*(c - o) > 0.0);
   double best = dirBar ? 0.25 : 0.0;
   const double wickAg = (d == 1) ? (MathMin(o, c) - l) : (h - MathMax(o, c));
   const double wickOt = (d == 1) ? (h - MathMax(o, c)) : (MathMin(o, c) - l);
   if(rng >= 0.5*A && wickAg >= 2.0*MathMax(body, 0.1*rng) && wickOt <= 0.5*wickAg)
      best = MathMax(best, 0.80);
   if(dirBar && d*(pc - po) < 0.0 && body >= MathAbs(pc - po))
     {
      const bool eng = (d == 1) ? (c >= po && o <= pc) : (c <= po && o >= pc);
      if(eng)
         best = MathMax(best, 0.90);
     }
   if(dirBar && body >= 0.55*rng && rng >= 0.8*A)
     {
      const bool thrust = (d == 1) ? (c > ph) : (c < pl);
      if(thrust)
         best = MathMax(best, 0.70);
     }
   return best;
  }

//--- liquidity sweep of the last swing / touch of key EMAs
double LevelScore(const int d, const int sH)
  {
   const int cm = g_cm;
   const int k = g_km[cm];
   if(k < 3)
      return 0.0;
   double best = 0.0;
   for(int a = 0; a <= 2; a++)
     {
      const int q = k - a;
      double lvl;
      bool has;
      if(d == 1)
        {
         lvl = g_tf[cm].b[q-1].slP;
         has = (g_tf[cm].b[q-1].slI >= 0);
        }
      else
        {
         lvl = g_tf[cm].b[q-1].shP;
         has = (g_tf[cm].b[q-1].shI >= 0);
        }
      if(!has)
         continue;
      bool sw;
      if(d == 1)
         sw = (g_tf[cm].b[q].l < lvl && g_tf[cm].b[k].c > lvl);
      else
         sw = (g_tf[cm].b[q].h > lvl && g_tf[cm].b[k].c < lvl);
      if(sw)
         best = MathMax(best, 1.0 - 0.2*a);
     }
   double ext = (d == 1) ? g_tf[cm].b[k].l : g_tf[cm].b[k].h;
   for(int a = 1; a <= 2; a++)
      ext = (d == 1) ? MathMin(ext, g_tf[cm].b[k-a].l) : MathMax(ext, g_tf[cm].b[k-a].h);
   const double cl = g_tf[cm].b[k].c;
   if(sH >= 0)
     {
      const int kh = g_km[sH];
      const double eh = g_tf[sH].b[kh].emaS;
      const double ah = MathMax(g_tf[sH].b[kh].atr, g_point);
      if(d == 1 && ext <= eh + 0.25*ah && cl >= eh - 0.25*ah)
         best = MathMax(best, 0.6);
      if(d == -1 && ext >= eh - 0.25*ah && cl <= eh + 0.25*ah)
         best = MathMax(best, 0.6);
     }
   const double eb = g_tf[cm].b[k].emaB;
   const double ac = MathMax(g_tf[cm].b[k].atr, g_point);
   if(k >= InpBaseMA)
     {
      if(d == 1 && ext <= eb + 0.2*ac && cl >= eb - 0.2*ac)
         best = MathMax(best, 0.5);
      if(d == -1 && ext >= eb - 0.2*ac && cl <= eb + 0.2*ac)
         best = MathMax(best, 0.5);
     }
   return best;
  }

//+------------------------------------------------------------------+
//| MTF bias: htf = timeframes above the chart TF, all = every TF   |
//+------------------------------------------------------------------+
void CalcBias(double &htf, double &all, double &weak)
  {
   double hiA = 0.0, hiW = 0.0, alA = 0.0, alW = 0.0;
   for(int s = 0; s < g_cnt; s++)
     {
      const int k = g_km[s];
      if(k < 0)
         continue;
      const double w = 1.0 + InpTFWeightSlope*s;
      const double v = g_tf[s].b[k].trend*(0.5 + 0.5*g_tf[s].b[k].tstr/100.0);
      alA += w*v;
      alW += w;
      if(s > g_cm)
        {
         hiA += w*v;
         hiW += w;
        }
     }
   all = (alW > 0.0) ? alA/alW : 0.0;
   htf = (hiW > 0.0) ? hiA/hiW : all;
   const int sg = (htf >= 0.15) ? 1 : ((htf <= -0.15) ? -1 : 0);
   double wa = 0.0, ww = 0.0;
   if(sg != 0)
     {
      for(int s = g_cm; s < g_cnt; s++)
        {
         const int k = g_km[s];
         if(k < 0)
            continue;
         if(g_tf[s].b[k].trend != sg)
            continue;
         const double w = 1.0 + InpTFWeightSlope*s;
         wa += w*g_tf[s].b[k].weak;
         ww += w;
        }
     }
   weak = (ww > 0.0) ? wa/ww : 0.0;
  }

int BiasColor(const double htf, const double weak)
  {
   if(htf >= 0.25)
      return (weak >= InpWeakLow) ? 1 : 0;
   if(htf <= -0.25)
      return (weak >= InpWeakLow) ? 3 : 4;
   return 2;
  }

//+------------------------------------------------------------------+
//| Evaluate a reversal in direction d (+1 up / -1 down)             |
//+------------------------------------------------------------------+
void EvalDir(const int d, const double htf, SEval &o)
  {
   o.score = 0.0; o.ctx = 0.0; o.wk = 0.0; o.ex = 0.0; o.dv = 0.0;
   o.sb = 0.0; o.cs = 0.0; o.cd = 0.0; o.lv = 0.0;
   o.groups = 0; o.depth = 0; o.cls = 1; o.gates = false; o.pass = false;
   const int cm = g_cm;
   const int kc = g_km[cm];
   if(kc < 0)
      return;

   double ctxChart = 0.0, ctxHiA = 0.0, ctxHiW = 0.0;
   double wkA = 0.0, wkW = 0.0;
   double csLoA = 0.0, csHiA = 0.0, csHiW = 0.0;
   int csLoN = 0, depth = 0;
   bool chain = true;
   int sH = -1, sL = -1;

   for(int s = 0; s < g_cnt; s++)
     {
      const int k = g_km[s];
      if(k < 0)
         continue;
      const double w = 1.0 + InpTFWeightSlope*s;
      const int trd = g_tf[s].b[k].trend;
      const double memOpp = (d == 1) ? g_tf[s].b[k].memDn : g_tf[s].b[k].memUp;

      //--- prior-trend context (chart TF and above)
      if(s == cm)
         ctxChart = memOpp/100.0;
      else
         if(s > cm)
           {
            ctxHiA += w*memOpp/100.0;
            ctxHiW += w;
            if(sH < 0)
               sH = s;
           }
         else
            sL = s;

      //--- weakening of the prior trend wherever it still exists
      double wks = -1.0;
      if(trd == -d)
         wks = g_tf[s].b[k].weak/100.0;
      else
         if(trd == 0)
           {
            if(memOpp >= 40.0)
               wks = 0.75;
           }
         else
           {
            if(memOpp >= 40.0)
               wks = 1.0;
           }
      if(wks >= 0.0)
        {
         wkA += w*wks;
         wkW += w;
        }

      //--- cascade: how far the flip has climbed from the lowest TF
      const double fs = FlipScore(g_tf[s].b[k], d);
      if(s <= cm)
        {
         csLoA += fs;
         csLoN++;
        }
      else
        {
         csHiA += w*fs;
         csHiW += w;
        }
      if(chain)
        {
         if(Flipped(g_tf[s].b[k], d))
            depth++;
         else
            chain = false;
        }
     }

   const double ctxHi = (ctxHiW > 0.0) ? ctxHiA/ctxHiW : ctxChart;
   o.ctx = Clamp(0.65*ctxChart + 0.35*ctxHi, 0.0, 1.0);
   o.wk  = (wkW > 0.0) ? Clamp(wkA/wkW, 0.0, 1.0) : 0.0;
   const double csLo = (csLoN > 0) ? csLoA/csLoN : 0.0;
   const double csHi = (csHiW > 0.0) ? csHiA/csHiW : csLo;
   o.cs = Clamp(0.65*csLo + 0.35*csHi, 0.0, 1.0);
   o.depth = depth;

   //--- exhaustion (chart TF + next higher TF)
   const double exC = ExhScore(g_tf[cm].b[kc], d);
   const double exH = (sH >= 0) ? ExhScore(g_tf[sH].b[g_km[sH]], d) : exC;
   o.ex = Clamp(0.65*exC + 0.35*exH, 0.0, 1.0);

   //--- divergence (chart TF, next higher, next lower)
   double dv = DivScore(g_tf[cm].b[kc], kc, d);
   if(sH >= 0)
      dv = MathMax(dv, 0.9*DivScore(g_tf[sH].b[g_km[sH]], g_km[sH], d));
   if(sL >= 0)
      dv = MathMax(dv, 0.6*DivScore(g_tf[sL].b[g_km[sL]], g_km[sL], d));
   o.dv = dv;

   //--- structure break (CHoCH)
   double sbq = BreakScore(g_tf[cm].b[kc], kc, d);
   if(sH >= 0)
      sbq = MathMax(sbq, BreakScore(g_tf[sH].b[g_km[sH]], g_km[sH], d));
   if(sL >= 0)
      sbq = MathMax(sbq, 0.8*BreakScore(g_tf[sL].b[g_km[sL]], g_km[sL], d));
   o.sb = sbq;

   o.cd = CandleScore(d);
   o.lv = LevelScore(d, sH);
   o.cls = (htf*d >= 0.15) ? 2 : 1;

   const double wsum = InpSCtx + InpSWeak + InpSExh + InpSDiv + InpSBreak + InpSCascade + InpSCandle + InpSLevel;
   if(wsum > 0.0)
      o.score = 100.0*(InpSCtx*o.ctx + InpSWeak*o.wk + InpSExh*o.ex + InpSDiv*o.dv +
                       InpSBreak*o.sb + InpSCascade*o.cs + InpSCandle*o.cd + InpSLevel*o.lv)/wsum;

   //--- confirmation groups
   int gcount = 0;
   if(o.wk >= InpWeakLow/100.0) gcount++;
   if(o.ex >= 0.5)              gcount++;
   if(o.dv >= 0.5)              gcount++;
   if(o.sb >= 0.5)              gcount++;
   if(o.cs >= 0.5)              gcount++;
   if(o.cd >= 0.6 || o.lv >= 0.6) gcount++;
   o.groups = gcount;

   const int needDepth = MathMin(g_P.minDepth, g_cnt);
   o.gates = (o.ctx >= g_P.minCtx) && (o.wk >= g_P.minWeak) && (o.cs >= g_P.minCascade) &&
             (o.depth >= needDepth) && (o.sb >= g_P.sbMin) && (!g_P.needCandle || o.cd >= 0.5);
   o.pass = o.gates && (o.groups >= g_P.minGroups) && (o.score >= g_P.minScore);
  }

//--- why a direction is not (yet) a signal
string BlockReason(const SEval &e)
  {
   if(e.pass)
      return "all conditions met";
   if(e.ctx <= 0.0 && e.wk <= 0.0)
      return "no prior trend to reverse";
   if(e.score < g_P.minScore)
      return "score " + IntegerToString((int)MathRound(e.score)) + " < " + IntegerToString((int)MathRound(g_P.minScore));
   if(e.groups < g_P.minGroups)
      return "confirmations " + IntegerToString(e.groups) + " < " + IntegerToString(g_P.minGroups);
   if(e.ctx < g_P.minCtx)
      return "prior-trend context " + DoubleToString(e.ctx, 2) + " < " + DoubleToString(g_P.minCtx, 2);
   if(e.wk < g_P.minWeak)
      return "weakening " + DoubleToString(e.wk, 2) + " < " + DoubleToString(g_P.minWeak, 2);
   if(e.cs < g_P.minCascade)
      return "lower-TF cascade " + DoubleToString(e.cs, 2) + " < " + DoubleToString(g_P.minCascade, 2);
   if(e.depth < MathMin(g_P.minDepth, g_cnt))
      return "cascade depth " + IntegerToString(e.depth) + " < " + IntegerToString(MathMin(g_P.minDepth, g_cnt));
   if(e.sb < g_P.sbMin)
      return "no structure break (CHoCH) yet";
   if(g_P.needCandle && e.cd < 0.5)
      return "no confirming candle";
   return "waiting for a fresh trigger";
  }

//--- invalidation level of a new signal
double SwingInv(const int d, const int kc)
  {
   const double A = MathMax(g_tf[g_cm].b[kc].atr, g_point);
   double ext = (d == 1) ? g_tf[g_cm].b[kc].l : g_tf[g_cm].b[kc].h;
   for(int q = MathMax(kc - 4, 0); q <= kc; q++)
      ext = (d == 1) ? MathMin(ext, g_tf[g_cm].b[q].l) : MathMax(ext, g_tf[g_cm].b[q].h);
   double inv = ext - d*0.2*A;
   const double entry = g_tf[g_cm].b[kc].c;
   if(MathAbs(entry - inv) < 0.8*A)
      inv = entry - d*0.8*A;
   return inv;
  }

//+------------------------------------------------------------------+
//| Chart objects: labels, level lines                               |
//+------------------------------------------------------------------+
void RingRemove(const string nm)
  {
   for(int i = 0; i < g_lblCnt; i++)
      if(g_lblNm[i] == nm)
        {
         for(int j = i; j < g_lblCnt - 1; j++)
            g_lblNm[j] = g_lblNm[j + 1];
         g_lblCnt--;
         ArrayResize(g_lblNm, g_lblCnt);
         return;
        }
  }

void RemoveLabel(const datetime T)
  {
   const string nm = g_pfx + "L_" + IntegerToString((long)T);
   if(ObjectFind(0, nm) >= 0)
      ObjectDelete(0, nm);
   RingRemove(nm);
  }

void AddLabel(const datetime T, const int dir, const double price, const double score, const int cls, const int grade)
  {
   if(!InpShowLabels || InpMaxLabels <= 0)
      return;
   const string nm = g_pfx + "L_" + IntegerToString((long)T);
   if(ObjectFind(0, nm) >= 0)
      ObjectDelete(0, nm);
   RingRemove(nm);
   if(!ObjectCreate(0, nm, OBJ_TEXT, 0, T, price))
      return;
   const string txt = Pick(dir > 0, "BUY ", "SELL ") + IntegerToString((int)MathRound(score)) + Pick(cls == 2, " TURN", " REV");
   ObjectSetString(0, nm, OBJPROP_TEXT, txt);
   ObjectSetString(0, nm, OBJPROP_FONT, InpFontName);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, MathMax(InpDashFont - 1, 7));
   ObjectSetInteger(0, nm, OBJPROP_COLOR, (dir > 0) ? g_th.bull : g_th.bear);
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR, (dir > 0) ? ANCHOR_UPPER : ANCHOR_LOWER);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   while(g_lblCnt >= InpMaxLabels && g_lblCnt > 0)
     {
      ObjectDelete(0, g_lblNm[0]);
      for(int j = 0; j < g_lblCnt - 1; j++)
         g_lblNm[j] = g_lblNm[j + 1];
      g_lblCnt--;
     }
   ArrayResize(g_lblNm, g_lblCnt + 1);
   g_lblNm[g_lblCnt++] = nm;
  }

void DrawSeg(const string key, const datetime t1, const datetime t2, const double price, const color col, const ENUM_LINE_STYLE style, const string txt)
  {
   const string nm = g_pfx + "V_" + key;
   ObjectDelete(0, nm);
   if(ObjectCreate(0, nm, OBJ_TREND, 0, t1, price, t2, price))
     {
      ObjectSetInteger(0, nm, OBJPROP_COLOR, col);
      ObjectSetInteger(0, nm, OBJPROP_STYLE, style);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, nm, OBJPROP_BACK, true);
     }
   const string nt = nm + "_t";
   ObjectDelete(0, nt);
   if(ObjectCreate(0, nt, OBJ_TEXT, 0, t2, price))
     {
      ObjectSetString(0, nt, OBJPROP_TEXT, txt + " " + DoubleToString(price, _Digits));
      ObjectSetString(0, nt, OBJPROP_FONT, InpFontName);
      ObjectSetInteger(0, nt, OBJPROP_FONTSIZE, MathMax(InpDashFont - 2, 7));
      ObjectSetInteger(0, nt, OBJPROP_COLOR, col);
      ObjectSetInteger(0, nt, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, nt, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nt, OBJPROP_HIDDEN, true);
     }
  }

void DrawLevels()
  {
   ObjectsDeleteAll(0, g_pfx + "V_");
   if(!InpShowLevels || g_lsDir == 0 || g_lsT == 0)
      return;
   const double R = MathAbs(g_lsEntry - g_lsInv);
   if(R <= 0.0)
      return;
   const datetime t2 = g_lsT + (datetime)(g_chartSec*45);
   DrawSeg("E", g_lsT, t2, g_lsEntry, g_th.dim, STYLE_DOT, "ENTRY");
   DrawSeg("I", g_lsT, t2, g_lsInv, g_th.bear, STYLE_SOLID, "INV");
   DrawSeg("1", g_lsT, t2, g_lsEntry + g_lsDir*1.5*R, g_th.bull, STYLE_DASH, "T1 1.5R");
   DrawSeg("2", g_lsT, t2, g_lsEntry + g_lsDir*3.0*R, g_th.bull, STYLE_DASH, "T2 3R");
  }

void DeleteChartObjects()
  {
   ObjectsDeleteAll(0, g_pfx + "L_");
   ObjectsDeleteAll(0, g_pfx + "V_");
   g_lblCnt = 0;
   ArrayResize(g_lblNm, 0);
  }

//+------------------------------------------------------------------+
//| Alerts                                                           |
//+------------------------------------------------------------------+
void FireAlert(const int dir, const double score, const int cls, const bool isWatch)
  {
   string txt = "TCR " + _Symbol + " " + TFName((ENUM_TIMEFRAMES)_Period) + ": ";
   if(isWatch)
      txt += Pick(dir > 0, "bullish reversal WATCH - downtrend weakening", "bearish reversal WATCH - uptrend weakening");
   else
     {
      txt += Pick(dir > 0, "BUY reversal", "SELL reversal");
      txt += Pick(cls == 2, " [TURN with HTF bias]", " [REV against HTF]");
      txt += " score " + IntegerToString((int)MathRound(score));
     }
   if(InpAlertPopup)
      Alert(txt);
   if(InpAlertPush)
      SendNotification(txt);
   if(InpAlertMail)
      SendMail("TCR Reversal Radar", txt);
   if(InpAlertSound != "")
      PlaySound(InpAlertSound);
  }

void AlertCheck(const datetime T, const int sd)
  {
   if(sd != 0)
     {
      if(T != g_lastAlertBar)
        {
         g_lastAlertBar = T;
         FireAlert(sd, g_sigScore, g_sigCls, false);
        }
      return;
     }
   if(g_watchDir != 0 && InpAlertWatch && T != g_lastWatchAlert)
     {
      g_lastWatchAlert = T;
      FireAlert(g_watchDir, 0.0, 0, true);
     }
  }

//+------------------------------------------------------------------+
//| Bar engine                                                       |
//+------------------------------------------------------------------+
void ClearBar(const int bar)
  {
   BufBuy[bar] = EMPTY_VALUE;  BufBuyC[bar] = 0.0;
   BufSell[bar] = EMPTY_VALUE; BufSellC[bar] = 0.0;
   BufBase[bar] = EMPTY_VALUE; BufBaseC[bar] = 2.0;
   BufWarn[bar] = EMPTY_VALUE; BufWarnC[bar] = 0.0;
   BufBuyScore[bar] = 0.0;
   BufSellScore[bar] = 0.0;
   BufBias[bar] = 0.0;
  }

void ResetSignalState()
  {
   g_lastBuyK = -100000;  g_lastSellK = -100000;
   g_lastWBuyK = -100000; g_lastWSellK = -100000;
   g_pBuy = false; g_pSell = false;
   g_wsBuy = false; g_wsSell = false;
   g_lsDir = 0; g_lsK = -1; g_lsT = 0; g_lsGrade = 0; g_lsCls = 0;
   g_lsScore = 0.0; g_lsEntry = 0.0; g_lsInv = 0.0;
   g_lsDirty = true;
  }

//--- evaluates one chart bar; returns +1 / -1 when a signal is produced
int EvalBar(const int bar, const datetime T, const bool live, const bool commit, const bool allowSig)
  {
   g_sigDir = 0;
   g_watchDir = 0;
   MapAll(T, live);
   const int cm = g_cm;
   const int kc = g_km[cm];
   if(kc < 0)
     {
      ClearBar(bar);
      return 0;
     }
   double htf, all, bw;
   CalcBias(htf, all, bw);
   SEval eb, es;
   EvalDir(1, htf, eb);
   EvalDir(-1, htf, es);

   const double A = MathMax(g_tf[cm].b[kc].atr, g_point);
   BufBuyScore[bar]  = eb.score;
   BufSellScore[bar] = es.score;
   BufBias[bar]      = htf*100.0;
   BufBase[bar]      = InpShowBase ? g_tf[cm].b[kc].emaS : EMPTY_VALUE;
   BufBaseC[bar]     = (double)BiasColor(htf, bw);
   BufBuy[bar] = EMPTY_VALUE;  BufBuyC[bar] = 0.0;
   BufSell[bar] = EMPTY_VALUE; BufSellC[bar] = 0.0;
   BufWarn[bar] = EMPTY_VALUE; BufWarnC[bar] = 0.0;
   if(!allowSig)
      return 0;

   //--- signal = fresh rising edge of "pass", class filter, cooldown
   bool sbuy  = eb.pass && !g_pBuy  && ClassOK(eb.cls) && (bar - g_lastBuyK  >= g_P.cooldown);
   bool ssell = es.pass && !g_pSell && ClassOK(es.cls) && (bar - g_lastSellK >= g_P.cooldown);
   if(sbuy && ssell)
     {
      if(eb.score >= es.score)
         ssell = false;
      else
         sbuy = false;
     }
   int sd = 0;
   if(sbuy)
      sd = 1;
   else
      if(ssell)
         sd = -1;

   if(sd != 0)
     {
      SEval e;
      if(sd == 1)
         e = eb;
      else
         e = es;
      int grade = 1;
      const double q = (e.score - g_P.minScore)/MathMax(100.0 - g_P.minScore, 1.0);
      if(q >= 0.22)
         grade = 2;
      else
         if(q < 0.07)
            grade = 0;
      const double off = InpArrowOffset*A;
      double apx;
      if(sd == 1)
        {
         apx = g_tf[cm].b[kc].l - off;
         if(InpShowArrows)
           {
            BufBuy[bar] = apx;
            BufBuyC[bar] = (double)grade;
           }
        }
      else
        {
         apx = g_tf[cm].b[kc].h + off;
         if(InpShowArrows)
           {
            BufSell[bar] = apx;
            BufSellC[bar] = (double)grade;
           }
        }
      g_sigDir = sd;
      g_sigScore = e.score;
      g_sigCls = e.cls;
      g_sigGrade = grade;
      AddLabel(T, sd, apx - sd*0.45*A, e.score, e.cls, grade);
      if(commit)
        {
         if(sd == 1)
            g_lastBuyK = bar;
         else
            g_lastSellK = bar;
         g_lsDir = sd;
         g_lsK = bar;
         g_lsT = T;
         g_lsGrade = grade;
         g_lsCls = e.cls;
         g_lsScore = e.score;
         g_lsEntry = g_tf[cm].b[kc].c;
         g_lsInv = SwingInv(sd, kc);
         g_lsDirty = true;
         g_eSig = e;
        }
     }
   else
      if(g_timing == (int)TIMING_LIVE && bar >= g_rtLast - 3)
         RemoveLabel(T);

   //--- early warning: prior trend weakening, no signal yet
   const bool wbOn  = (!eb.pass) && eb.ctx >= 0.15 && eb.wk*100.0 >= InpWeakLow && eb.score >= 0.6*g_P.minScore;
   const bool wsOn  = (!es.pass) && es.ctx >= 0.15 && es.wk*100.0 >= InpWeakLow && es.score >= 0.6*g_P.minScore;
   const bool wbOff = eb.pass || eb.ctx < 0.10 || eb.wk*100.0 < 0.6*InpWeakLow;
   const bool wsOff = es.pass || es.ctx < 0.10 || es.wk*100.0 < 0.6*InpWeakLow;
   bool wbE = wbOn && !g_wsBuy  && (bar - g_lastWBuyK  >= g_P.cooldown);
   bool wsE = wsOn && !g_wsSell && (bar - g_lastWSellK >= g_P.cooldown);
   bool nsBuy = g_wsBuy, nsSell = g_wsSell;       // watch episodes use hysteresis: one dot per weakening episode
   if(!g_wsBuy)
     {
      if(wbOn)
         nsBuy = true;
     }
   else
      if(wbOff)
         nsBuy = false;
   if(!g_wsSell)
     {
      if(wsOn)
         nsSell = true;
     }
   else
      if(wsOff)
         nsSell = false;
   if(wbE && wsE)
     {
      if(eb.wk >= es.wk)
         wsE = false;
      else
         wbE = false;
     }
   if(sd != 0)
     {
      wbE = false;
      wsE = false;
     }
   if(wbE)
      g_watchDir = 1;
   else
      if(wsE)
         g_watchDir = -1;
   if(g_watchDir != 0 && InpShowWatch)
     {
      if(g_watchDir == 1)
        {
         BufWarn[bar] = g_tf[cm].b[kc].l - 0.35*A;
         BufWarnC[bar] = 0.0;
        }
      else
        {
         BufWarn[bar] = g_tf[cm].b[kc].h + 0.35*A;
         BufWarnC[bar] = 1.0;
        }
     }
   if(commit)
     {
      g_pBuy = eb.pass;
      g_pSell = es.pass;
      g_wsBuy = nsBuy;
      g_wsSell = nsSell;
      if(wbE)
         g_lastWBuyK = bar;
      if(wsE)
         g_lastWSellK = bar;
     }
   return sd;
  }

//--- evaluates [start .. rt-1]; closed bars first, then the forming bar
void RunEngine(const int rt, const int pc, const datetime &time[])
  {
   if(rt < 3 || ArraySize(BufBuy) < rt || ArraySize(time) < rt)
      return;
   if(!g_tf[g_cm].ready)
      return;
   g_rtLast = rt;
   const bool full = (pc <= 0 || pc > rt);
   const int first = MathMax(rt - InpHistoryBars, 0);
   int start;
   if(full)
     {
      for(int i = 0; i < first; i++)
         ClearBar(i);
      ResetSignalState();
      DeleteChartObjects();
      start = first;
     }
   else
      start = MathMax(pc - 1, first);

   const int lastClosed = rt - 2;
   for(int bar = start; bar <= lastClosed; bar++)
     {
      const int sd = EvalBar(bar, time[bar], false, true, true);
      if(!full && bar == lastClosed)
         AlertCheck(time[bar], sd);
     }
   const int fb = rt - 1;
   if(g_timing == (int)TIMING_LIVE)
     {
      const int sd2 = EvalBar(fb, time[fb], true, false, true);
      AlertCheck(time[fb], sd2);
     }
   else
      EvalBar(fb, time[fb], true, false, false);
   if(g_lsDirty)
     {
      DrawLevels();
      g_lsDirty = false;
     }
  }

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
#define MAX_DOBJ 230

string   g_dn[MAX_DOBJ];
int      g_dx[MAX_DOBJ];
int      g_dy[MAX_DOBJ];
string   g_dt[MAX_DOBJ];
color    g_dc[MAX_DOBJ];
int      g_dw[MAX_DOBJ];
int      g_dCnt = 0;
int      g_pw = 340;
int      g_ph = 300;
int      g_px = 0;
int      g_py = 0;
int      g_lastCW = 0;
int      g_lastCH = 0;
string   g_fontB = "Segoe UI Bold";

int      g_iBg = -1, g_iSub = -1, g_iColBtn = -1, g_iSum = -1;
int      g_iTfName[MAX_TF], g_iTfArr[MAX_TF], g_iTfFill[MAX_TF], g_iTfState[MAX_TF];
int      g_iTfWeak[MAX_TF], g_iTfMom[MAX_TF], g_iTfFront[MAX_TF];
int      g_iBiasFill = -1, g_iBiasTxt = -1, g_iBiasWk = -1, g_iRadHdr = -1;
int      g_iBuyFill = -1, g_iBuyTick = -1, g_iBuyScore = -1, g_iBuyStat = -1;
int      g_iSelFill = -1, g_iSelTick = -1, g_iSelScore = -1, g_iSelStat = -1;
int      g_iCompHdr = -1, g_iBlock = -1, g_iLast1 = -1, g_iLast2 = -1;
int      g_iCompFill[8];
int      g_iLvlTxt = -1, g_iClsBtn = -1, g_iTimBtn = -1;

#define BAR_TF   60
#define BAR_RAD  150
#define BAR_BIAS 120
#define BAR_COMP 44

int U(const int v)
  {
   return (int)MathRound(v*g_u);
  }

string F0(const double v)
  {
   return IntegerToString((int)MathRound(v));
  }

void InitTheme()
  {
   if(InpDashTheme == THEME_LIGHT)
     {
      g_th.bg     = C'246,248,251';
      g_th.header = C'230,235,243';
      g_th.border = C'196,205,219';
      g_th.text   = C'28,36,50';
      g_th.dim    = C'112,122,140';
      g_th.track  = C'221,227,237';
      g_th.bull   = C'0,150,90';
      g_th.bear   = C'209,52,66';
      g_th.amber  = C'204,136,0';
      g_th.orange = C'219,100,30';
      g_th.accent = C'30,110,220';
      g_th.btn    = C'224,230,241';
      g_th.btnTxt = C'28,36,50';
     }
   else
     {
      g_th.bg     = C'18,22,30';
      g_th.header = C'28,35,48';
      g_th.border = C'52,62,80';
      g_th.text   = C'214,222,235';
      g_th.dim    = C'126,138,158';
      g_th.track  = C'40,49,64';
      g_th.bull   = C'38,200,130';
      g_th.bear   = C'240,84,96';
      g_th.amber  = C'255,176,46';
      g_th.orange = C'255,128,64';
      g_th.accent = C'90,165,255';
      g_th.btn    = C'42,52,70';
      g_th.btnTxt = C'214,222,235';
     }
  }

void InitGlyphs()
  {
   G_UP  = ShortToString(0x25B2);
   G_DN  = ShortToString(0x25BC);
   G_RNG = ShortToString(0x25AC);
  }

//--- object registry ---------------------------------------------------
int DReg(const string nm, const int x, const int y, const color c)
  {
   if(g_dCnt >= MAX_DOBJ)
     {
      ObjectDelete(0, nm);
      return -1;
     }
   const int i = g_dCnt++;
   g_dn[i] = nm;
   g_dx[i] = x;
   g_dy[i] = y;
   g_dt[i] = "~|~";
   g_dc[i] = (color)0xFFFFFFFE;
   g_dw[i] = -1;
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, g_px + x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, g_py + y);
   return i;
  }

int DObjRect(const string key, const int x, const int y, const int w, const int h, const color bg, const color bd)
  {
   const string nm = g_pfx + "D_" + key;
   ObjectDelete(0, nm);
   if(!ObjectCreate(0, nm, OBJ_RECTANGLE_LABEL, 0, 0, 0))
      return -1;
   ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, nm, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, bd);
   ObjectSetInteger(0, nm, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, nm, OBJPROP_ZORDER, 0);
   const int i = DReg(nm, x, y, bg);
   if(i >= 0)
     {
      g_dc[i] = bg;
      g_dw[i] = w;
     }
   return i;
  }

int DObjLabel(const string key, const int x, const int y, const string txt, const color col, const int fsz, const bool bold = false)
  {
   const string nm = g_pfx + "D_" + key;
   ObjectDelete(0, nm);
   if(!ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0))
      return -1;
   ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetString(0, nm, OBJPROP_FONT, bold ? g_fontB : InpFontName);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, fsz);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, col);
   ObjectSetString(0, nm, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, nm, OBJPROP_ZORDER, 1);
   const int i = DReg(nm, x, y, col);
   if(i >= 0)
     {
      g_dt[i] = txt;
      g_dc[i] = col;
     }
   return i;
  }

int DObjButton(const string key, const int x, const int y, const int w, const int h, const string txt, const int fsz)
  {
   const string nm = g_pfx + "D_" + key;
   ObjectDelete(0, nm);
   if(!ObjectCreate(0, nm, OBJ_BUTTON, 0, 0, 0))
      return -1;
   ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, nm, OBJPROP_YSIZE, h);
   ObjectSetString(0, nm, OBJPROP_FONT, g_fontB);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, fsz);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, g_th.btnTxt);
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, g_th.btn);
   ObjectSetInteger(0, nm, OBJPROP_BORDER_COLOR, g_th.border);
   ObjectSetString(0, nm, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, nm, OBJPROP_STATE, false);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, nm, OBJPROP_ZORDER, 5);
   const int i = DReg(nm, x, y, g_th.btnTxt);
   if(i >= 0)
     {
      g_dt[i] = txt;
      g_dc[i] = g_th.btnTxt;
     }
   return i;
  }

//--- cached updates -----------------------------------------------------
void SetT(const int i, const string txt, const color col)
  {
   if(i < 0)
      return;
   if(g_dt[i] != txt)
     {
      ObjectSetString(0, g_dn[i], OBJPROP_TEXT, txt);
      g_dt[i] = txt;
     }
   if(g_dc[i] != col)
     {
      ObjectSetInteger(0, g_dn[i], OBJPROP_COLOR, col);
      g_dc[i] = col;
     }
  }

void SetFill(const int i, const int fullW, const double frac, const color col)
  {
   if(i < 0)
      return;
   int w = (int)MathRound(fullW*Clamp(frac, 0.0, 1.0));
   const bool vis = (w >= 1);
   if(w < 1)
      w = 1;
   if(g_dw[i] != w)
     {
      ObjectSetInteger(0, g_dn[i], OBJPROP_XSIZE, w);
      g_dw[i] = w;
     }
   const color cc = vis ? col : g_th.track;
   if(g_dc[i] != cc)
     {
      ObjectSetInteger(0, g_dn[i], OBJPROP_BGCOLOR, cc);
      ObjectSetInteger(0, g_dn[i], OBJPROP_COLOR, cc);
      g_dc[i] = cc;
     }
  }

void SetX(const int i, const int x)
  {
   if(i < 0 || g_dx[i] == x)
      return;
   g_dx[i] = x;
   ObjectSetInteger(0, g_dn[i], OBJPROP_XDISTANCE, g_px + x);
  }

void DashCalcOrigin()
  {
   const int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   const int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   g_lastCW = cw;
   g_lastCH = ch;
   const bool right = (InpDashCorner == CORNER_RIGHT_UPPER || InpDashCorner == CORNER_RIGHT_LOWER);
   const bool lower = (InpDashCorner == CORNER_LEFT_LOWER || InpDashCorner == CORNER_RIGHT_LOWER);
   g_px = right ? MathMax(cw - g_pw - InpDashX, 0) : InpDashX;
   g_py = lower ? MathMax(ch - g_ph - InpDashY, 0) : InpDashY;
  }

void DashReposition()
  {
   DashCalcOrigin();
   for(int i = 0; i < g_dCnt; i++)
     {
      ObjectSetInteger(0, g_dn[i], OBJPROP_XDISTANCE, g_px + g_dx[i]);
      ObjectSetInteger(0, g_dn[i], OBJPROP_YDISTANCE, g_py + g_dy[i]);
     }
  }

void DashDelete()
  {
   ObjectsDeleteAll(0, g_pfx + "D_");
   g_dCnt = 0;
  }

//+------------------------------------------------------------------+
//| Layout                                                           |
//+------------------------------------------------------------------+
void BuildDashboard()
  {
   DashDelete();
   for(int i = 0; i < MAX_TF; i++)
     {
      g_iTfName[i] = -1; g_iTfArr[i] = -1; g_iTfFill[i] = -1; g_iTfState[i] = -1;
      g_iTfWeak[i] = -1; g_iTfMom[i] = -1; g_iTfFront[i] = -1;
     }
   for(int i = 0; i < 8; i++)
      g_iCompFill[i] = -1;
   g_iBg = -1; g_iSub = -1; g_iColBtn = -1; g_iSum = -1;
   g_iBiasFill = -1; g_iBiasTxt = -1; g_iBiasWk = -1; g_iRadHdr = -1;
   g_iBuyFill = -1; g_iBuyTick = -1; g_iBuyScore = -1; g_iBuyStat = -1;
   g_iSelFill = -1; g_iSelTick = -1; g_iSelScore = -1; g_iSelStat = -1;
   g_iCompHdr = -1; g_iBlock = -1; g_iLast1 = -1; g_iLast2 = -1;
   g_iLvlTxt = -1; g_iClsBtn = -1; g_iTimBtn = -1;
   if(!InpShowDash)
      return;

   g_u = Clamp(InpDashFont/9.0, 0.7, 2.2);
   const int fs = InpDashFont;
   const int fsm = MathMax(fs - 1, 6);
   g_pw = U(340);
   g_ph = U(420);
   g_fontB = InpFontName + " Bold";
   DashCalcOrigin();

   g_iBg = DObjRect("bg", 0, 0, g_pw, g_ph, g_th.bg, g_th.border);
   DObjRect("hdr", 1, 1, g_pw - 2, U(24), g_th.header, g_th.header);
   DObjLabel("title", U(8), U(5), "TCR  REVERSAL RADAR", g_th.text, fs, true);
   g_iSub = DObjLabel("sub", U(160), U(6), "", g_th.dim, fsm);
   g_iColBtn = DObjButton("B_COL", g_pw - U(26), U(3), U(20), U(18), g_collapsed ? "+" : "-", fs);
   int y = U(30);

   if(g_collapsed)
     {
      g_iSum = DObjLabel("sum", U(8), y, "", g_th.text, fs);
      y += U(22);
      g_ph = y;
      ObjectSetInteger(0, g_pfx + "D_bg", OBJPROP_YSIZE, g_ph);
      DashReposition();
      return;
     }

   //--- column captions
   DObjLabel("c1", U(8),   y, "TF",       g_th.dim, fsm);
   DObjLabel("c2", U(44),  y, "dir",      g_th.dim, fsm);
   DObjLabel("c3", U(66),  y, "strength", g_th.dim, fsm);
   DObjLabel("c4", U(134), y, "state",    g_th.dim, fsm);
   DObjLabel("c5", U(236), y, "weak",     g_th.dim, fsm);
   DObjLabel("c6", U(272), y, "mom",      g_th.dim, fsm);
   DObjLabel("c7", U(304), y, "front",    g_th.dim, fsm);
   y += U(15);

   //--- timeframe rows: highest TF at the top, lowest at the bottom
   const int rh = U(17);
   for(int r = 0; r < g_cnt; r++)
     {
      const int s = g_cnt - 1 - r;
      const int ry = y + r*rh;
      const string id = IntegerToString(s);
      g_iTfName[s]  = DObjLabel("tn" + id, U(8), ry + U(2), TFName(g_tfs[s]), (s == g_cm) ? g_th.accent : g_th.text, fs, true);
      g_iTfArr[s]   = DObjLabel("ta" + id, U(46), ry + U(2), G_RNG, g_th.dim, fs);
      DObjRect("tt" + id, U(66), ry + U(5), U(BAR_TF), U(7), g_th.track, g_th.track);
      g_iTfFill[s]  = DObjRect("tf" + id, U(66), ry + U(5), U(1), U(7), g_th.track, g_th.track);
      g_iTfState[s] = DObjLabel("ts" + id, U(134), ry + U(2), "-", g_th.dim, fs);
      g_iTfWeak[s]  = DObjLabel("tw" + id, U(236), ry + U(3), "", g_th.dim, fsm);
      g_iTfMom[s]   = DObjLabel("tm" + id, U(268), ry + U(3), "", g_th.dim, fsm);
      g_iTfFront[s] = DObjLabel("tr" + id, U(314), ry + U(2), "", g_th.amber, fs);
     }
   y += g_cnt*rh + U(3);
   DObjRect("sp1", U(8), y, g_pw - U(16), 1, g_th.border, g_th.border);
   y += U(6);

   //--- MTF bias
   DObjLabel("bl", U(8), y + U(1), "HTF bias", g_th.dim, fs);
   DObjRect("bt", U(70), y + U(5), U(BAR_BIAS), U(8), g_th.track, g_th.track);
   g_iBiasFill = DObjRect("bf", U(70), y + U(5), U(1), U(8), g_th.track, g_th.track);
   g_iBiasTxt = DObjLabel("bx", U(196), y + U(1), "", g_th.text, fs, true);
   g_iBiasWk  = DObjLabel("bw", U(270), y + U(2), "", g_th.dim, fsm);
   y += U(22);

   //--- reversal radar
   g_iRadHdr = DObjLabel("rh", U(8), y, "", g_th.dim, fsm);
   y += U(15);
   DObjLabel("rb", U(8), y + U(1), "BUY", g_th.bull, fs, true);
   DObjRect("rbt", U(44), y + U(4), U(BAR_RAD), U(9), g_th.track, g_th.track);
   g_iBuyFill  = DObjRect("rbf", U(44), y + U(4), U(1), U(9), g_th.track, g_th.track);
   g_iBuyTick  = DObjRect("rbk", U(44), y + U(2), 2, U(13), g_th.text, g_th.text);
   g_iBuyScore = DObjLabel("rbs", U(200), y + U(1), "", g_th.text, fs, true);
   g_iBuyStat  = DObjLabel("rbz", U(228), y + U(2), "", g_th.dim, fsm);
   y += U(19);
   DObjLabel("rs", U(8), y + U(1), "SELL", g_th.bear, fs, true);
   DObjRect("rst", U(44), y + U(4), U(BAR_RAD), U(9), g_th.track, g_th.track);
   g_iSelFill  = DObjRect("rsf", U(44), y + U(4), U(1), U(9), g_th.track, g_th.track);
   g_iSelTick  = DObjRect("rsk", U(44), y + U(2), 2, U(13), g_th.text, g_th.text);
   g_iSelScore = DObjLabel("rss", U(200), y + U(1), "", g_th.text, fs, true);
   g_iSelStat  = DObjLabel("rsz", U(228), y + U(2), "", g_th.dim, fsm);
   y += U(23);

   //--- score components of the leading side
   g_iCompHdr = DObjLabel("ch", U(8), y, "", g_th.dim, fsm);
   y += U(15);
   const string cn[8] = {"Ctx", "Weak", "Exh", "Div", "Brk", "Casc", "Cndl", "Lvl"};
   const int cw = (g_pw - U(16))/4;
   for(int c = 0; c < 8; c++)
     {
      const int cx = U(8) + (c % 4)*cw;
      const int cy = y + (c/4)*U(16);
      DObjLabel("cl" + IntegerToString(c), cx, cy, cn[c], g_th.dim, fsm);
      DObjRect("ct" + IntegerToString(c), cx + U(32), cy + U(5), U(BAR_COMP), U(6), g_th.track, g_th.track);
      g_iCompFill[c] = DObjRect("cf" + IntegerToString(c), cx + U(32), cy + U(5), U(1), U(6), g_th.track, g_th.track);
     }
   y += U(34);
   DObjRect("sp2", U(8), y, g_pw - U(16), 1, g_th.border, g_th.border);
   y += U(6);

   //--- status lines
   g_iBlock = DObjLabel("bk", U(8), y, "", g_th.dim, fsm);
   y += U(17);
   g_iLast1 = DObjLabel("l1", U(8), y, "", g_th.text, fs, true);
   y += U(16);
   g_iLast2 = DObjLabel("l2", U(8), y, "", g_th.dim, fsm);
   y += U(19);
   DObjRect("sp3", U(8), y, g_pw - U(16), 1, g_th.border, g_th.border);
   y += U(6);

   //--- controls
   DObjButton("B_DN", U(8), y, U(22), U(20), "-", fs);
   g_iLvlTxt = DObjLabel("lv", U(36), y + U(3), "", g_th.text, fs, true);
   DObjButton("B_UP", U(108), y, U(22), U(20), "+", fs);
   g_iClsBtn = DObjButton("B_CLS", U(140), y, U(52), U(20), "ALL", fsm);
   g_iTimBtn = DObjButton("B_TIM", U(198), y, U(60), U(20), "CLOSE", fsm);
   y += U(26);

   g_ph = y;
   ObjectSetInteger(0, g_pfx + "D_bg", OBJPROP_YSIZE, g_ph);
   DashReposition();
  }

//+------------------------------------------------------------------+
//| Live data for the dashboard                                      |
//+------------------------------------------------------------------+
int Phase(const TFBar &x)
  {
   if(x.trend == 0)
      return 0;
   if(x.weak >= InpWeakHigh)
      return 3;
   if(x.weak >= InpWeakLow)
      return 2;
   return 1;
  }

string StateText(const int t, const int ph, const double tstr)
  {
   if(t == 0)
      return "Range";
   const string d = (t > 0) ? "UP " : "DOWN ";
   if(ph == 3)
      return d + "exhausted";
   if(ph == 2)
      return d + "weakening";
   return d + ((tstr >= 50.0) ? "strong" : "trend");
  }

string RadarStatus(const SEval &e, const bool watch, const color base, color &col)
  {
   if(e.pass)
     {
      if(!ClassOK(e.cls))
        {
         col = g_th.dim;
         return "filtered";
        }
      col = base;
      return (e.cls == 2) ? "TURN active" : "REV active";
     }
   if(e.score >= g_P.minScore - 12.0 && e.ctx >= 0.10)
     {
      col = g_th.amber;
      return "NEAR";
     }
   if(watch)
     {
      col = g_th.orange;
      return "WATCH";
     }
   col = g_th.dim;
   return "-";
  }

string BiasText()
  {
   if(MathAbs(g_dBias) < 0.15)
      return "NEUTRAL";
   return ((g_dBias > 0.0) ? "BULL " : "BEAR ") + F0(MathAbs(g_dBias)*100.0);
  }

void DashData()
  {
   if(!g_tf[g_cm].ready)
      return;
   datetime T = 0;
   bool live = InpDashLive;
   if(!live)
     {
      const int n = g_tf[g_cm].n;
      if(n >= 2)
         T = g_tf[g_cm].b[n-2].t;
      else
         live = true;
     }
   MapAll(T, live);
   double htf, all, bw;
   CalcBias(htf, all, bw);
   g_dBias = htf;
   g_dAll = all;
   g_dBiasWeak = bw;
   EvalDir(1, htf, g_dBull);
   EvalDir(-1, htf, g_dBear);
   g_dWatchBuy  = (!g_dBull.pass) && g_dBull.ctx >= 0.15 && g_dBull.wk*100.0 >= InpWeakLow && g_dBull.score >= 0.6*g_P.minScore;
   g_dWatchSell = (!g_dBear.pass) && g_dBear.ctx >= 0.15 && g_dBear.wk*100.0 >= InpWeakLow && g_dBear.score >= 0.6*g_P.minScore;
  }

void DashDraw()
  {
   SetT(g_iSub, _Symbol + "  " + TFName((ENUM_TIMEFRAMES)_Period) + "  " + ((g_timing == (int)TIMING_CLOSE) ? "bar-close" : "live"), g_th.dim);
   const color biasCol = (MathAbs(g_dBias) < 0.15) ? g_th.dim : ((g_dBias > 0.0) ? g_th.bull : g_th.bear);

   if(g_collapsed)
     {
      SetT(g_iSum, BiasText() + "   BUY " + F0(g_dBull.score) + "   SELL " + F0(g_dBear.score), biasCol);
      return;
     }

   //--- timeframe rows
   int front = -1;
   const int bsg = (MathAbs(g_dAll) >= 0.15) ? ((g_dAll > 0.0) ? 1 : -1) : 0;
   for(int s = g_cnt - 1; s >= 0; s--)
     {
      const int k = g_km[s];
      if(k < 0)
        {
         SetT(g_iTfArr[s], G_RNG, g_th.dim);
         SetFill(g_iTfFill[s], U(BAR_TF), 0.0, g_th.dim);
         SetT(g_iTfState[s], g_tf[s].ready ? "no data yet" : "loading...", g_th.dim);
         SetT(g_iTfWeak[s], "", g_th.dim);
         SetT(g_iTfMom[s], "", g_th.dim);
         SetT(g_iTfFront[s], "", g_th.amber);
         continue;
        }
      const int t = g_tf[s].b[k].trend;
      const int ph = Phase(g_tf[s].b[k]);
      const color cd = (t > 0) ? g_th.bull : ((t < 0) ? g_th.bear : g_th.dim);
      const color cp = (ph == 1) ? cd : ((ph == 2) ? g_th.amber : ((ph == 3) ? g_th.orange : g_th.dim));
      SetT(g_iTfArr[s], (t > 0) ? G_UP : ((t < 0) ? G_DN : G_RNG), cd);
      SetFill(g_iTfFill[s], U(BAR_TF), (t != 0) ? g_tf[s].b[k].tstr/100.0 : 0.0, cp);
      SetT(g_iTfState[s], StateText(t, ph, g_tf[s].b[k].tstr), cp);
      SetT(g_iTfWeak[s], (t != 0) ? "W" + F0(g_tf[s].b[k].weak) : "", (ph >= 2) ? cp : g_th.dim);
      const double mm = g_tf[s].b[k].mom;
      string mt = F0(mm);
      if(mm > 0.5)
         mt = "+" + mt;
      SetT(g_iTfMom[s], mt, (mm > 0.5) ? g_th.bull : ((mm < -0.5) ? g_th.bear : g_th.dim));
      bool isFront = false;
      if(front < 0 && bsg != 0 && (t != bsg || ph >= 2))
        {
         front = s;
         isFront = true;
        }
      SetT(g_iTfFront[s], isFront ? ShortToString(0x25C4) : "", g_th.amber);
     }

   //--- bias
   SetFill(g_iBiasFill, U(BAR_BIAS), MathAbs(g_dBias), biasCol);
   SetT(g_iBiasTxt, BiasText(), biasCol);
   SetT(g_iBiasWk, (MathAbs(g_dBias) >= 0.15) ? "weak " + F0(g_dBiasWeak) + "%" : "", (g_dBiasWeak >= InpWeakLow) ? g_th.amber : g_th.dim);

   //--- radar
   SetT(g_iRadHdr, "REVERSAL SCORE   need " + F0(g_P.minScore) + "+  and " + IntegerToString(g_P.minGroups) + "/6 confirmations", g_th.dim);
   const int tickX = U(44) + (int)MathRound(U(BAR_RAD)*Clamp(g_P.minScore/100.0, 0.0, 1.0));
   SetFill(g_iBuyFill, U(BAR_RAD), g_dBull.score/100.0, g_th.bull);
   SetX(g_iBuyTick, tickX);
   SetT(g_iBuyScore, F0(g_dBull.score), g_th.text);
   color sc;
   string st = RadarStatus(g_dBull, g_dWatchBuy, g_th.bull, sc);
   SetT(g_iBuyStat, st, sc);
   SetFill(g_iSelFill, U(BAR_RAD), g_dBear.score/100.0, g_th.bear);
   SetX(g_iSelTick, tickX);
   SetT(g_iSelScore, F0(g_dBear.score), g_th.text);
   st = RadarStatus(g_dBear, g_dWatchSell, g_th.bear, sc);
   SetT(g_iSelStat, st, sc);

   //--- components of the leading side
   const bool leadBuy = (g_dBull.score >= g_dBear.score);
   SEval le;
   if(leadBuy)
      le = g_dBull;
   else
      le = g_dBear;
   SetT(g_iCompHdr, "COMPONENTS  " + Pick(leadBuy, "BUY", "SELL") + "   class " + Pick(le.cls == 2, "TURN (with HTF)", "REV (vs HTF)") +
        "   depth " + IntegerToString(le.depth) + "/" + IntegerToString(g_cnt), g_th.dim);
   double cv[8];
   cv[0] = le.ctx; cv[1] = le.wk; cv[2] = le.ex; cv[3] = le.dv;
   cv[4] = le.sb;  cv[5] = le.cs; cv[6] = le.cd; cv[7] = le.lv;
   for(int c = 0; c < 8; c++)
     {
      const color cc = (cv[c] >= 0.5) ? (leadBuy ? g_th.bull : g_th.bear) : ((cv[c] >= 0.25) ? g_th.amber : g_th.dim);
      SetFill(g_iCompFill[c], U(BAR_COMP), cv[c], cc);
     }

   //--- verdict / last signal
   SetT(g_iBlock, (le.pass ? "OK: " : "Blocked: ") + BlockReason(le), le.pass ? (leadBuy ? g_th.bull : g_th.bear) : g_th.orange);
   if(g_lsDir == 0)
     {
      SetT(g_iLast1, "Last signal: none yet", g_th.dim);
      SetT(g_iLast2, "", g_th.dim);
     }
   else
     {
      const int ago = (g_rtLast - 1) - g_lsK;
      SetT(g_iLast1, "Last: " + Pick(g_lsDir > 0, "BUY ", "SELL ") + Pick(g_lsCls == 2, "TURN ", "REV ") + F0(g_lsScore) +
           "   " + IntegerToString(ago) + " bars ago", (g_lsDir > 0) ? g_th.bull : g_th.bear);
      SetT(g_iLast2, "Entry " + DoubleToString(g_lsEntry, _Digits) + "   INV " + DoubleToString(g_lsInv, _Digits) +
           "   T1 " + DoubleToString(g_lsEntry + g_lsDir*1.5*MathAbs(g_lsEntry - g_lsInv), _Digits), g_th.dim);
     }

   //--- controls
   SetT(g_iLvlTxt, (g_level == 0) ? "Manual" : "Strict " + IntegerToString(g_level) + "/10", g_th.text);
   SetT(g_iClsBtn, (g_sigClass == (int)SC_ALL) ? "ALL" : ((g_sigClass == (int)SC_REV) ? "REV" : "TURN"), g_th.btnTxt);
   SetT(g_iTimBtn, (g_timing == (int)TIMING_CLOSE) ? "CLOSE" : "LIVE", g_th.btnTxt);
  }

void UpdateDashboard(const bool force)
  {
   if(!InpShowDash || g_dCnt == 0 || !g_ready)
      return;
   const ulong now = GetTickCount64();
   if(!force && now - g_lastDash < 250)
      return;
   g_lastDash = now;
   if(!g_tf[g_cm].ready)
      return;
   DashData();
   DashDraw();
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Runtime state (dashboard buttons) survives timeframe changes     |
//+------------------------------------------------------------------+
string GVName(const string key)
  {
   return "TCR_" + IntegerToString(ChartID()) + "_" + key;
  }

void SaveOne(const string key, const double v)
  {
   const string nm = GVName(key);
   GlobalVariableTemp(nm);
   GlobalVariableSet(nm, v);
  }

void SaveState()
  {
   SaveOne("lvl", (double)g_level);
   SaveOne("cls", (double)g_sigClass);
   SaveOne("tim", (double)g_timing);
   SaveOne("col", g_collapsed ? 1.0 : 0.0);
  }

void LoadState()
  {
   string nm = GVName("lvl");
   if(GlobalVariableCheck(nm))
      g_level = (int)Clamp(GlobalVariableGet(nm), 0.0, 10.0);
   nm = GVName("cls");
   if(GlobalVariableCheck(nm))
      g_sigClass = (int)Clamp(GlobalVariableGet(nm), 0.0, 2.0);
   nm = GVName("tim");
   if(GlobalVariableCheck(nm))
      g_timing = (int)Clamp(GlobalVariableGet(nm), 0.0, 1.0);
   nm = GVName("col");
   if(GlobalVariableCheck(nm))
      g_collapsed = (GlobalVariableGet(nm) > 0.5);
  }

void ClearState()
  {
   GlobalVariableDel(GVName("lvl"));
   GlobalVariableDel(GVName("cls"));
   GlobalVariableDel(GVName("tim"));
   GlobalVariableDel(GVName("col"));
  }

//+------------------------------------------------------------------+
//| Re-run the whole evaluation (after a dashboard change / HTF load)|
//+------------------------------------------------------------------+
void FullRecalc()
  {
   if(!g_ready || !g_tf[g_cm].ready)
      return;
   const int total = Bars(_Symbol, (ENUM_TIMEFRAMES)_Period);
   if(total < 10 || total != g_rtLast || ArraySize(BufBuy) != total)
      return;
   datetime tt[];
   ArraySetAsSeries(tt, false);
   if(CopyTime(_Symbol, (ENUM_TIMEFRAMES)_Period, 0, total, tt) != total)
      return;
   RunEngine(total, 0, tt);
   g_needFull = false;
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   g_point = _Point;
   if(g_point <= 0.0)
      g_point = 0.00001;
   g_chartSec = PeriodSeconds((ENUM_TIMEFRAMES)_Period);
   if(g_chartSec <= 0)
      g_chartSec = 60;

   if(InpFastMA < 2 || InpSlowMA <= InpFastMA || InpBaseMA <= InpSlowMA || InpADXPeriod < 2 || InpATRPeriod < 2 ||
      InpRSIPeriod < 2 || InpMACDFast < 2 || InpMACDSlow <= InpMACDFast || InpMACDSig < 2 || InpSwingLen < 2 ||
      InpSlopeBars < 1 || InpMemBars < 5 || InpWeakLook < 3 || InpHistoryBars < 100)
     {
      Print("TCR: invalid input parameters (check EMA order Fast < Slow < Base, MACD Fast < Slow, minimum periods).");
      return INIT_PARAMETERS_INCORRECT;
     }

   SetIndexBuffer(0, BufBuy,       INDICATOR_DATA);
   SetIndexBuffer(1, BufBuyC,      INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, BufSell,      INDICATOR_DATA);
   SetIndexBuffer(3, BufSellC,     INDICATOR_COLOR_INDEX);
   SetIndexBuffer(4, BufBase,      INDICATOR_DATA);
   SetIndexBuffer(5, BufBaseC,     INDICATOR_COLOR_INDEX);
   SetIndexBuffer(6, BufWarn,      INDICATOR_DATA);
   SetIndexBuffer(7, BufWarnC,     INDICATOR_COLOR_INDEX);
   SetIndexBuffer(8, BufBuyScore,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(9, BufSellScore, INDICATOR_CALCULATIONS);
   SetIndexBuffer(10, BufBias,     INDICATOR_CALCULATIONS);
   ArraySetAsSeries(BufBuy, false);
   ArraySetAsSeries(BufBuyC, false);
   ArraySetAsSeries(BufSell, false);
   ArraySetAsSeries(BufSellC, false);
   ArraySetAsSeries(BufBase, false);
   ArraySetAsSeries(BufBaseC, false);
   ArraySetAsSeries(BufWarn, false);
   ArraySetAsSeries(BufWarnC, false);
   ArraySetAsSeries(BufBuyScore, false);
   ArraySetAsSeries(BufSellScore, false);
   ArraySetAsSeries(BufBias, false);
   for(int p = 0; p < 4; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetInteger(3, PLOT_ARROW, 159);
   IndicatorSetString(INDICATOR_SHORTNAME, "TCR Reversal Radar");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   g_level = (int)Clamp((double)InpStrictLevel, 0.0, 10.0);
   g_sigClass = (int)InpSigClass;
   g_timing = (int)InpTiming;
   g_collapsed = false;
   LoadState();
   BuildParams();
   BuildLadder();
   InitTFData();
   InitTheme();
   InitGlyphs();
   g_lblCnt = 0;
   ArrayResize(g_lblNm, 0);
   g_lastAlertBar = 0;
   g_lastWatchAlert = 0;
   g_rtLast = 0;
   g_needFull = true;
   g_ready = true;
   BuildDashboard();
   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ObjectsDeleteAll(0, g_pfx);
   if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE || reason == REASON_PARAMETERS)
      ClearState();
   ChartRedraw(0);
  }

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(!g_ready || rates_total < 10)
      return 0;
   ArraySetAsSeries(time, false);
   SyncData();
   if(!g_tf[g_cm].ready)
      return 0;
   const bool full = (prev_calculated <= 0) || g_needFull || (prev_calculated > rates_total);
   RunEngine(rates_total, full ? 0 : prev_calculated, time);
   g_needFull = false;
   UpdateDashboard(false);
   return rates_total;
  }

void OnTimer()
  {
   if(!g_ready)
      return;
   SyncData();
   if(g_needFull)
      FullRecalc();
   UpdateDashboard(true);
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(!g_ready)
      return;
   if(id == CHARTEVENT_CHART_CHANGE)
     {
      if(g_dCnt > 0)
        {
         const int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
         const int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
         if(cw != g_lastCW || ch != g_lastCH)
           {
            DashReposition();
            ChartRedraw(0);
           }
        }
      return;
     }
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;
   if(StringFind(sparam, g_pfx + "D_B_") != 0)
      return;
   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   bool recalc = false, rebuild = false;
   if(sparam == g_pfx + "D_B_UP")
     {
      if(g_level < 10)
        {
         g_level++;
         recalc = true;
        }
     }
   else
      if(sparam == g_pfx + "D_B_DN")
        {
         if(g_level > 0)
           {
            g_level--;
            recalc = true;
           }
        }
      else
         if(sparam == g_pfx + "D_B_CLS")
           {
            g_sigClass = (g_sigClass + 1) % 3;
            recalc = true;
           }
         else
            if(sparam == g_pfx + "D_B_TIM")
              {
               g_timing = 1 - g_timing;
               recalc = true;
              }
            else
               if(sparam == g_pfx + "D_B_COL")
                 {
                  g_collapsed = !g_collapsed;
                  rebuild = true;
                 }
   SaveState();
   if(recalc)
     {
      BuildParams();
      g_needFull = true;
      FullRecalc();
     }
   if(rebuild)
      BuildDashboard();
   UpdateDashboard(true);
  }
//+------------------------------------------------------------------+
