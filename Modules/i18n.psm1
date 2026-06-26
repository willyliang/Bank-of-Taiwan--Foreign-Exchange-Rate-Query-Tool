#Requires -Version 5.1
# =============================================================================
# i18n.psm1 — Internationalization Module for Exchange Rate Application
# Provides bilingual (zh/en) translation hashtable and helper functions.
# =============================================================================

# -----------------------------------------------------------------------------
# Translation Data
# Keys are identical in both zh and en; values differ by language.
# Access pattern: $script:Lang['zh']['key'] or $script:Lang[$lang]['key']
# -----------------------------------------------------------------------------

$script:Lang = [ordered]@{
    zh = [ordered]@{
        # ── 1. Currency Names ───────────────────────────────────────────────
        currency_usd = '美金'
        currency_jpy = '日圓'
        currency_eur = '歐元'
        currency_gbp = '英鎊'
        currency_cny = '人民幣'
        currency_hkd = '港幣'
        currency_sgd = '新加坡幣'
        currency_aud = '澳幣'
        currency_cad = '加幣'
        currency_chf = '瑞士法郎'
        currency_nzd = '紐西蘭幣'
        currency_thb = '泰銖'
        currency_php = '披索'
        currency_idr = '印尼盾'
        currency_krw = '韓元'
        currency_vnd = '越南盾'
        currency_myr = '馬來西亞林吉特'
        currency_zar = '南非幣'
        currency_sek = '瑞典克朗'

        # ── 2. Currency Names — English (Get-CurrencyNameEn) ───────────────
        currency_usd_en = 'US Dollar'
        currency_jpy_en = 'Japanese Yen'
        currency_eur_en = 'Euro'
        currency_gbp_en = 'British Pound'
        currency_cny_en = 'Chinese Yuan'
        currency_hkd_en = 'Hong Kong Dollar'
        currency_sgd_en = 'Singapore Dollar'
        currency_aud_en = 'Australian Dollar'
        currency_cad_en = 'Canadian Dollar'
        currency_chf_en = 'Swiss Franc'
        currency_nzd_en = 'New Zealand Dollar'
        currency_thb_en = 'Thai Baht'
        currency_php_en = 'Philippine Peso'
        currency_idr_en = 'Indonesian Rupiah'
        currency_krw_en = 'South Korean Won'
        currency_vnd_en = 'Vietnamese Dong'
        currency_myr_en = 'Malaysian Ringgit'
        currency_zar_en = 'South African Rand'
        currency_sek_en = 'Swedish Krona'

        # ── 3. Series Names (chart series.Name — must match ChartBuilder) ──
        series_cash_buy  = '現金買入'
        series_cash_sell = '現金賣出'
        series_spot_buy  = '即期買入'
        series_spot_sell = '即期賣出'

        # ── 4. Period Display Names ────────────────────────────────────────
        period_today = '本日'
        period_1m    = '本月'
        period_3m    = '3個月'
        period_6m    = '半年'
        period_1y    = '1年'
        period_3y    = '3年'
        period_5y    = '5年'
        period_10y   = '10年'

        # ── 5. UI Display Text ─────────────────────────────────────────────
        form_title         = '台灣銀行外匯查詢工具'
        currency_header    = '貨幣選擇'
        search_placeholder = '搜尋貨幣...'
        chart_no_data      = '尚無資料'
        chart_title        = '歷史匯率曲線'
        rate_na            = 'N/A'
        rate_dash          = '--'
        btn_pin            = '置頂'
        btn_refresh        = '重新整理'

        # ── 6. Status Messages ─────────────────────────────────────────────
        status_ready               = '就緒 ✓'
        status_reading_today       = '讀取本日資料...'
        status_reading_historical  = '讀取中... ({0}/{1})'
        status_reading_in_progress = '讀取中... (0/{0})'
        status_loading_chart       = '{0}  讀取匯率資料中...'
        status_fetch_failed        = '讀取失敗 (網路問題)'
        status_cached              = '已快取: {0} 筆'
        status_total_records       = '共 {0} 筆'
        status_fetching_rates      = '讀取即時匯率...'
        status_refreshing          = '重新整理中...'
        status_refresh_failed      = '重新整理失敗: {0}'

        # ── 7. Rate Display Labels ─────────────────────────────────────────
        label_cash_buy    = '現金買入:'
        label_cash_sell   = '現金賣出:'
        label_spot_buy    = '即期買入:'
        label_spot_sell   = '即期賣出:'
        label_update_time = '更新時間:'

        # ── 8. Converter ───────────────────────────────────────────────────
        converter_header  = '匯率換算'
        rate_type_spot    = '即期'
        rate_type_cash    = '現金'
        label_twd_currency = 'TWD 台幣'
        converter_info_na = '尚無匯率資料'
        converter_no_type = '此幣別無此類匯率資料'
        converter_info_format = '{0}賣出: {1} | {0}買入: {2} | 1 TWD ≈ {3} {4}'

        # ── 9. AI Analysis Panel ───────────────────────────────────────────
        ai_panel_header = '匯率智能分析'
        btn_ai_enhance  = 'AI 增強分析'
        ai_initial      = '選擇貨幣與期間後，將自動分析匯率趨勢並提供買入/賣出建議...'

        # Analysis state messages
        ai_analyzing          = '🔄 正在分析 {0} 匯率趨勢...'
        ai_waiting_data       = '⏳ 等待資料讀取完成後分析...'
        ai_no_spot_data       = '📊 本日無即期匯率資料，無法進行分析。'
        ai_insufficient_hist  = '📊 歷史資料不足（{0} 筆），至少需要 5 筆資料才能進行分析。`n請稍候資料讀取完成後再試。'
        ai_local_complete     = '📊 本地分析完成，但資料不足以產生完整建議。'
        ai_analysis_failed    = '⚠ 分析失敗: {0}'

        # Enhancement state messages
        ai_calling_provider      = '🔄 正在呼叫 AI 增強分析 ({0})...'
        ai_enhancing             = '🤖 AI 增強分析中 ({0})，請稍候...'
        ai_no_spot_data_ai       = '📊 本日無即期匯率資料，無法進行 AI 分析。'
        ai_insufficient_hist_ai  = '📊 歷史資料不足，無法進行 AI 分析。'
        ai_timeout               = '⚠ AI 回應超時（5 分鐘），請檢查網路或更換模型。`n`n切換幣別/期間可返回本地分析報告'
        ai_enhance_failed        = '⚠ AI 增強分析失敗: {0}`n`n切換幣別/期間可返回本地分析報告'
        ai_enhance_error_output  = '⚠ AI 增強分析失敗 ({0}): {1}`n`n切換幣別/期間可返回本地分析報告'
        ai_enhance_no_result     = '⚠ AI 增強分析未返回結果，請檢查網路連線。`n`n切換幣別/期間可返回本地分析報告'
        ai_success               = '🤖 AI 增強分析 ({0})`n`n{1}`n`n━━━━━━━━━━━━━━━━━━━━━`n切換幣別/期間可返回本地分析報告'

        # ── 10. AI Provider Dialog ──────────────────────────────────────────
        dialog_ai_model    = '選擇 AI 模型'
        label_ai_model     = 'AI 模型:'
        label_base_url     = 'Base URL:'
        label_model_name   = 'Model:'
        label_api_key      = 'API Key:'
        btn_show           = '顯示'
        btn_bypass_proxy   = '略過系統 Proxy'
        btn_ok             = '確定'
        btn_cancel         = '取消'
        btn_close          = '關閉'
        hint_enter_api_key = '請輸入您的 API Key'
        hint_no_api_key    = '此模型無需 API Key'
        err_url_required   = '請輸入 API Base URL。'
        err_key_required   = '此模型需要 API Key，請輸入。'
        dialog_title_missing = '缺少必要欄位'
        dialog_title_copy  = '複製成功'
        msg_link_copied    = '已複製下載連結到剪貼簿！'

        # Ollama dialogs
        dialog_ollama_install = 'Ollama 安裝指引'
        ollama_not_installed  = '偵測到系統尚未安裝 Ollama。`n`n請依下列步驟安裝：`n  1. 前往 https://ollama.com/download`n  2. 下載 Windows 版本並安裝`n  3. 安裝完成後重新啟動本程式`n`n下載連結：`nhttps://ollama.com/download'
        btn_copy_link        = '複製下載連結'
        dialog_ollama_starting = '啟動 Ollama'
        ollama_not_running   = 'Ollama 服務尚未啟動，將嘗試在背景啟動…'
        ollama_start_failed  = '無法啟動 Ollama 服務。請手動在終端機執行「ollama serve」後再試。'
        dialog_title_start_fail = '啟動失敗'
        dialog_pull_model    = '下載 Ollama 模型'
        ollama_no_models     = '本機尚未安裝任何 Ollama 模型。`n請輸入要下載的模型名稱（預設 llama3.2:3b，約 2GB）：'
        btn_download_model   = '下載模型'
        dialog_downloading   = '下載模型中'
        ollama_downloading   = "正在下載模型 ''{0}''，請稍候…`n這可能需要幾分鐘，取決於模型大小與網速。"
        err_unknown          = '未知錯誤'
        dialog_download_failed = '下載失敗'
        err_download_failed  = '模型下載失敗：{0}'
        err_download_exception = '下載程序異常: {0}'

        # ── 11. OllamaHelper Return Messages ────────────────────────────────
        ollama_download_success    = "模型 ''{0}'' 下載完成"
        ollama_download_incomplete = '下載未完成，最後狀態: {0}'
        ollama_download_error      = '下載失敗: {0}'

        # ── 12. RateAnalyzer Summary Strings ────────────────────────────────
        stats_no_data = '無資料，無法計算統計指標。'

        # Position descriptions
        position_near_low   = '接近低點'
        position_near_high  = '接近高點'
        position_weak       = '偏弱'
        position_strong     = '偏強'
        position_neutral    = '中性'

        # Build-Summary narrative parts
        summary_pos_format  = '目前即期賣出匯率 {0} 位於近30日第 {1} 百分位，{2}。'
        summary_spot_only   = '目前即期賣出匯率 {0}。'
        trend_rising        = 'SMA5 > SMA20，短期趨勢上升。'
        trend_falling       = 'SMA5 < SMA20，短期趨勢下降。'
        trend_consolidating = 'SMA5 ≈ SMA20，短期趨勢盤整。'
        rsi_format          = 'RSI={0}，{1}。'

        # RSI label
        rsi_overbought      = '超買'
        rsi_oversold        = '超賣'
        rsi_label_neutral   = '中性'

        # Trend labels
        trend_up            = '上升'
        trend_down          = '下降'
        trend_consolidate   = '盤整'

        # ── 13. Get-RateRecommendation — Recommendations ───────────────────
        recommendation_buy_strong  = '強烈建議買入'
        recommendation_buy         = '建議買入'
        recommendation_hold        = '觀望'
        recommendation_hold_sell   = '建議觀望/賣出'
        recommendation_sell_strong = '強烈建議賣出'

        # Cross-signal labels
        signal_bullish      = '看多'
        signal_bearish      = '看空'
        signal_diverged     = '分歧'
        strength_weak       = '弱'
        strength_strong     = '強'

        # Cross-signal list labels
        signal_rsi_bullish  = 'RSI 偏多'
        signal_rsi_bearish  = 'RSI 偏空'
        signal_sma_rising   = 'SMA 上升'
        signal_sma_falling  = 'SMA 下降'
        signal_macd_bullish = 'MACD 多頭'
        signal_macd_bearish = 'MACD 空頭'
        signal_bb_lower     = '布林接近下軌'
        signal_bb_upper     = '布林接近上軌'
        signal_pct_low      = '百分位偏低'
        signal_pct_high     = '百分位偏高'

        # Trend strength labels
        trend_strength_bull_strong  = '強勢多頭'
        trend_strength_bull_weak    = '弱勢多頭'
        trend_strength_consolidate  = '盤整'
        trend_strength_bear_weak    = '弱勢空頭'
        trend_strength_bear_strong  = '強勢空頭'

        # Risk level labels
        risk_high   = '高'
        risk_medium = '中'
        risk_low    = '低'

        # Position percent descriptions
        pct_pos_low    = '低點'
        pct_pos_high   = '高點'
        pct_pos_middle = '中間'

        # Bollinger position labels
        bb_near_lower = '接近下軌'
        bb_near_upper = '接近上軌'
        bb_middle     = '通道中間'

        # Bandwidth labels
        bw_high    = '高波動'
        bw_low     = '低波動'
        bw_normal  = '正常波動'

        # MACD labels
        macd_bullish = '多頭'
        macd_bearish = '空頭'
        macd_neutral = '中性'

        # RSI score description
        rsi_score_overbought = '偏強'
        rsi_score_oversold   = '偏弱'
        rsi_score_neutral    = '中性'

        # ── 14. DetailedReport Section Headers ──────────────────────────────
        report_header_line  = '═══════════════════════════════'
        report_header       = '  {0} 匯率綜合分析報告 — {1}'
        report_score_header = '📌 綜合評分: {0}  →  {1}'
        report_tech_header  = '  技術指標明細'
        report_trend_header    = '📈 趨勢指標'
        report_momentum_header = '📊 動量指標'
        report_volatility_header = '📐 波動指標'
        report_position_header   = '📏 位置指標'
        report_risk_header   = '  趨勢強度與風險評估'
        report_cross_header  = '  多重訊號共識'
        report_rec_header    = '  綜合建議'

        # Trend section
        sma_values       = '  SMA5: {0}  |  SMA20: {1}'
        sma_trend_format = '  趨勢: {0} ({1}分)'

        # Momentum section
        rsi_format_detail  = '  RSI(14): {0}  →  {1} ({2}分)'
        macd_values        = '  MACD: {0}  |  訊號線: {1}  |  柱狀: {2}'
        macd_judgement     = '  MACD 判定: {0} ({1}分)'

        # Volatility section
        bb_values        = '  布林通道: 上軌 {0}  |  中軌 {1}  |  下軌 {2}'
        percentb_format  = '  %B: {0}%  →  {1} ({2}分)'
        bandwidth_format = '  帶寬: {0}%  →  {1} ({2}分)'

        # Position section
        percentile_detail = '  30日百分位: {0}%  →  接近{1} ({2}分)'
        percentile_na     = '  30日百分位: N/A'

        # Trend Strength & Risk section
        trend_strength_fmt = '📊 趨勢強度: {0}'
        trend_components   = '  （綜合 SMA 趨勢 + MACD 動能 + 布林帶寬）'
        risk_fmt           = '{0} 風險等級: {1}'
        risk_reason_bw     = '帶寬較高 ({0}%)'
        risk_reason_rsi    = 'RSI 處於極端值 ({0})'
        risk_reason_normal = '  （各項指標波動與偏離程度正常）'
        risk_reason_format = '  （原因: {0}）'

        # Cross-Signal section
        signal_diverged_fmt  = '⚖️ 多空訊號分歧：看多 {0} 項 / 看空 {1} 項'
        signal_diverged_hint = '  目前指標尚未形成共識，建議觀望為主。'
        signal_consensus_fmt = '{0} 多重訊號共識: {1}{2}'
        signal_counts_fmt    = '  看多 {0} 項 / 看空 {1} 項'
        signal_list_fmt      = '  共識訊號: {0}'
        signal_strong_bull   = '  ⮕ 多項指標一致看多，訊號可靠度較高，可適度加碼。'
        signal_strong_bear   = '  ⮕ 多項指標一致看空，訊號可靠度較高，宜保守操作。'
        signal_weak_hint     = '  ⮕ 共識程度尚可，建議搭配其他訊號確認後再行動。'

        # Consensus description labels (used in signal_consensus_fmt)
        consensus_desc_strong = '（強共識）'
        consensus_desc_weak   = '（弱共識）'

        # Narrative recommendation
        rec_pos_near_low2    = '目前 {0} 即期賣出匯率 {1} 位於近30日第 {2} 百分位，接近低點。'
        rec_pos_near_high2   = '目前 {0} 即期賣出匯率 {1} 位於近30日第 {2} 百分位，接近高點。'
        rec_pos_low          = '目前 {0} 即期賣出匯率 {1} 位於近30日第 {2} 百分位，偏低。'
        rec_pos_high         = '目前 {0} 即期賣出匯率 {1} 位於近30日第 {2} 百分位，偏高。'
        rec_pos_neutral      = '目前 {0} 即期賣出匯率 {1} 位於近30日第 {2} 百分位，中間。'
        rec_pos_other        = '目前 {0} 即期賣出匯率 {1} 位於近30日第 {2} 百分位，{3}。'
        rec_rsi_oversold     = 'RSI 為 {0} 處於超賣區間，短期有反彈可能。'
        rec_rsi_overbought   = 'RSI 為 {0} 處於超買區間，短期有回調風險。'
        rec_rsi_neutral      = 'RSI 為 {0}，處於中性區間。'
        rec_macd_positive    = 'MACD 柱狀圖由負轉正，顯示動能轉強。'
        rec_macd_negative    = 'MACD 柱狀圖仍為負值，顯示動能偏弱。'
        rec_bb_near_lower    = '布林通道 %B 僅 {0}%，價格接近下軌支撐。'
        rec_bb_near_upper    = '布林通道 %B 達 {0}%，價格接近上軌壓力。'
        rec_consensus_bull   = '多項指標形成看多共識，訊號可靠度提升。'
        rec_consensus_bear   = '多項指標形成看空共識，訊號可靠度提升。'
        rec_final_format     = '綜合評分 {0} 分，{1}。'
        rec_suit_buy         = '適合有外幣需求的民眾分批買入。'
        rec_suit_sell        = '建議暫緩買入，或可考慮分批賣出。'
        rec_suit_hold        = '建議持續觀察，等待更明確訊號。'

        # Action Advice
        action_advice_header = '💡 操作建議'
        action_bullet_format = '  • {0}'

        # Risk disclaimer
        risk_disclaimer = '⚠ 以上分析僅供參考，不構成任何投資建議。投資有風險，請自行審慎評估。'

        # ── 15. Action Advice Strings ────────────────────────────────────────
        advice_rsi_oversold     = '若 RSI 回升至 40 以上，可考慮分批進場買入'
        advice_rsi_overbought   = '若 RSI 回落至 60 以下，可考慮分批賣出'
        advice_rsi_weak_oversold = 'RSI 偏弱但未極端超賣，觀察是否進一步跌破 30 形成更強買入訊號'
        advice_rsi_weak_obought = 'RSI 偏強但未極端超買，觀察是否進一步突破 70 形成更強賣出訊號'
        advice_sma_death_cross  = '關注 SMA5 是否向下跌穿 SMA20 形成死亡交叉，作為趨勢反轉警訊'
        advice_sma_golden_cross = '關注 SMA5 是否向上穿越 SMA20 形成黃金交叉，作為趨勢反轉訊號'
        advice_sma_near         = 'SMA5 與 SMA20 接近，留意即將出現的方向突破'
        advice_macd_bull_align  = 'MACD 多頭排列中，若柱狀圖縮小需留意動能減弱'
        advice_macd_bear_align  = 'MACD 空頭排列中，若柱狀圖縮小需留意跌勢趨緩'
        advice_bb_lower_break   = '價格接近布林下軌 ({0})，若跌破且帶寬擴大，恐加速下跌'
        advice_bb_upper_break   = '價格接近布林上軌 ({0})，若突破且帶寬擴大，可能續強'

        # ── 16. AI System Prompts ───────────────────────────────────────────
        ai_system_prompt_zh = @'
你是一位專業的外匯匯率分析師。請根據提供的統計指標進行分析，並給出簡潔的買入/賣出/觀望建議（3-5 句話），使用繁體中文回覆。

你的分析必須：
1. 引用具體數字（目前匯率、SMA 值、RSI、百分位數）來支持你的判斷
2. 提及目前匯率是否接近近期高點或低點
3. 結合 RSI 指標判斷超買或超賣狀態
4. 結合 SMA 均線判斷趨勢方向
5. 在建議末尾加上免責聲明：「以上分析僅供參考，不構成任何投資建議。投資有風險，請自行審慎評估。」
'@
        ai_system_prompt_en = @'
You are a professional foreign exchange rate analyst. Based on the provided statistical indicators, analyze the FX data and provide a concise buy/sell/hold recommendation (3-5 sentences), responding in English.

Your analysis must:
1. Cite specific numbers (current rate, SMA values, RSI, percentile) to support your judgment
2. Note whether the current rate is near recent highs or lows
3. Use the RSI indicator to determine overbought or oversold conditions
4. Use the SMA moving averages to determine trend direction
5. End with a disclaimer: ''This analysis is for reference only and does not constitute any investment advice. Please evaluate risks carefully before making any decisions.''

When responding, prioritize English output. Use the same key indicator labels as provided (SMA5, SMA20, RSI14, etc.).
'@
    }

    en = [ordered]@{
        # ── 1. Currency Names ───────────────────────────────────────────────
        currency_usd = 'US Dollar'
        currency_jpy = 'Japanese Yen'
        currency_eur = 'Euro'
        currency_gbp = 'British Pound'
        currency_cny = 'Chinese Yuan'
        currency_hkd = 'Hong Kong Dollar'
        currency_sgd = 'Singapore Dollar'
        currency_aud = 'Australian Dollar'
        currency_cad = 'Canadian Dollar'
        currency_chf = 'Swiss Franc'
        currency_nzd = 'New Zealand Dollar'
        currency_thb = 'Thai Baht'
        currency_php = 'Philippine Peso'
        currency_idr = 'Indonesian Rupiah'
        currency_krw = 'South Korean Won'
        currency_vnd = 'Vietnamese Dong'
        currency_myr = 'Malaysian Ringgit'
        currency_zar = 'South African Rand'
        currency_sek = 'Swedish Krona'

        # ── 2. Currency Names — English (Get-CurrencyNameEn) ───────────────
        currency_usd_en = 'US Dollar'
        currency_jpy_en = 'Japanese Yen'
        currency_eur_en = 'Euro'
        currency_gbp_en = 'British Pound'
        currency_cny_en = 'Chinese Yuan'
        currency_hkd_en = 'Hong Kong Dollar'
        currency_sgd_en = 'Singapore Dollar'
        currency_aud_en = 'Australian Dollar'
        currency_cad_en = 'Canadian Dollar'
        currency_chf_en = 'Swiss Franc'
        currency_nzd_en = 'New Zealand Dollar'
        currency_thb_en = 'Thai Baht'
        currency_php_en = 'Philippine Peso'
        currency_idr_en = 'Indonesian Rupiah'
        currency_krw_en = 'South Korean Won'
        currency_vnd_en = 'Vietnamese Dong'
        currency_myr_en = 'Malaysian Ringgit'
        currency_zar_en = 'South African Rand'
        currency_sek_en = 'Swedish Krona'

        # ── 3. Series Names ─────────────────────────────────────────────────
        series_cash_buy  = 'Cash Buy'
        series_cash_sell = 'Cash Sell'
        series_spot_buy  = 'Spot Buy'
        series_spot_sell = 'Spot Sell'

        # ── 4. Period Display Names ────────────────────────────────────────
        period_today = 'Today'
        period_1m    = 'This Month'
        period_3m    = '3 Months'
        period_6m    = '6 Months'
        period_1y    = '1 Year'
        period_3y    = '3 Years'
        period_5y    = '5 Years'
        period_10y   = '10 Years'

        # ── 5. UI Display Text ─────────────────────────────────────────────
        form_title         = 'Taiwan Bank FX Rate Viewer'
        currency_header    = 'Currency'
        search_placeholder = 'Search currency...'
        chart_no_data      = 'No Data'
        chart_title        = 'Historical Exchange Rate'
        rate_na            = 'N/A'
        rate_dash          = '--'
        btn_pin            = 'Pin'
        btn_refresh        = 'Refresh'

        # ── 6. Status Messages ─────────────────────────────────────────────
        status_ready               = 'Ready ✓'
        status_reading_today       = 'Loading today''s data...'
        status_reading_historical  = 'Loading... ({0}/{1})'
        status_reading_in_progress = 'Loading... (0/{0})'
        status_loading_chart       = '{0}  Loading FX data...'
        status_fetch_failed        = 'Fetch failed (network issue)'
        status_cached              = 'Cached: {0} records'
        status_total_records       = '{0} records'
        status_fetching_rates      = 'Fetching live rates...'
        status_refreshing          = 'Refreshing...'
        status_refresh_failed      = 'Refresh failed: {0}'

        # ── 7. Rate Display Labels ─────────────────────────────────────────
        label_cash_buy    = 'Cash Buy:'
        label_cash_sell   = 'Cash Sell:'
        label_spot_buy    = 'Spot Buy:'
        label_spot_sell   = 'Spot Sell:'
        label_update_time = 'Updated:'

        # ── 8. Converter ───────────────────────────────────────────────────
        converter_header  = 'Currency Converter'
        rate_type_spot    = 'Spot'
        rate_type_cash    = 'Cash'
        label_twd_currency = 'TWD NTD'
        converter_info_na = 'No rate data available'
        converter_no_type = 'No rate data for this type'
        converter_info_format = '{0} Sell: {1} | {0} Buy: {2} | 1 TWD ≈ {3} {4}'

        # ── 9. AI Analysis Panel ───────────────────────────────────────────
        ai_panel_header = 'FX Intelligence Analysis'
        btn_ai_enhance  = 'AI Enhancement'
        ai_initial      = 'Select a currency and period to analyze FX trends and get buy/sell recommendations...'

        # Analysis state messages
        ai_analyzing          = '🔄 Analyzing {0} FX trends...'
        ai_waiting_data       = '⏳ Waiting for data to load before analyzing...'
        ai_no_spot_data       = '📊 No spot rate data for today. Cannot analyze.'
        ai_insufficient_hist  = '📊 Insufficient historical data ({0} points), at least 5 required for analysis.`nPlease wait for data to load and try again.'
        ai_local_complete     = '📊 Local analysis complete, but insufficient data for full recommendations.'
        ai_analysis_failed    = '⚠ Analysis failed: {0}'

        # Enhancement state messages
        ai_calling_provider      = '🔄 Calling AI enhancement ({0})...'
        ai_enhancing             = '🤖 AI enhancement in progress ({0}), please wait...'
        ai_no_spot_data_ai       = '📊 No spot rate data for today. Cannot run AI analysis.'
        ai_insufficient_hist_ai  = '📊 Insufficient historical data. Cannot run AI analysis.'
        ai_timeout               = '⚠ AI response timed out (5 minutes). Check your network or try a different model.`n`nSwitch currency/period to return to local analysis report'
        ai_enhance_failed        = '⚠ AI enhancement failed: {0}`n`nSwitch currency/period to return to local analysis report'
        ai_enhance_error_output  = '⚠ AI enhancement failed ({0}): {1}`n`nSwitch currency/period to return to local analysis report'
        ai_enhance_no_result     = '⚠ AI enhancement returned no result. Check your network connection.`n`nSwitch currency/period to return to local analysis report'
        ai_success               = '🤖 AI Enhancement ({0})`n`n{1}`n`n━━━━━━━━━━━━━━━━━━━━━`nSwitch currency/period to return to local analysis report'

        # ── 10. AI Provider Dialog ──────────────────────────────────────────
        dialog_ai_model     = 'Select AI Model'
        label_ai_model      = 'AI Model:'
        label_base_url      = 'Base URL:'
        label_model_name    = 'Model:'
        label_api_key       = 'API Key:'
        btn_show            = 'Show'
        btn_bypass_proxy    = 'Bypass System Proxy'
        btn_ok              = 'OK'
        btn_cancel          = 'Cancel'
        btn_close           = 'Close'
        hint_enter_api_key  = 'Please enter your API Key'
        hint_no_api_key     = 'This model does not require an API Key'
        err_url_required    = 'Please enter the API Base URL.'
        err_key_required    = 'This model requires an API Key. Please enter it.'
        dialog_title_missing = 'Required Field Missing'
        dialog_title_copy   = 'Copy Success'
        msg_link_copied     = 'Download link copied to clipboard!'

        # Ollama dialogs
        dialog_ollama_install   = 'Ollama Installation Guide'
        ollama_not_installed    = 'Ollama is not installed on this system.`n`nTo install:`n  1. Go to https://ollama.com/download`n  2. Download the Windows version and install`n  3. Restart this application after installation`n`nDownload link:`nhttps://ollama.com/download'
        btn_copy_link           = 'Copy Download Link'
        dialog_ollama_starting  = 'Starting Ollama'
        ollama_not_running      = 'Ollama service is not running. Attempting to start it in the background...'
        ollama_start_failed     = 'Failed to start Ollama service. Please run "ollama serve" in a terminal manually and try again.'
        dialog_title_start_fail = 'Startup Failed'
        dialog_pull_model       = 'Download Ollama Model'
        ollama_no_models        = 'No Ollama models are installed on this machine.`nPlease enter the model name to download (default llama3.2:3b, ~2GB):'
        btn_download_model      = 'Download Model'
        dialog_downloading      = 'Downloading Model'
        ollama_downloading      = "Downloading model ''{0}'', please wait...`nThis may take several minutes depending on model size and network speed."
        err_unknown             = 'Unknown error'
        dialog_download_failed  = 'Download Failed'
        err_download_failed     = 'Model download failed: {0}'
        err_download_exception  = 'Download process error: {0}'

        # ── 11. OllamaHelper Return Messages ────────────────────────────────
        ollama_download_success    = "Model ''{0}'' download complete"
        ollama_download_incomplete = 'Download incomplete. Last status: {0}'
        ollama_download_error      = 'Download failed: {0}'

        # ── 12. RateAnalyzer Summary Strings ────────────────────────────────
        stats_no_data = 'No data available. Cannot compute statistics.'

        # Position descriptions
        position_near_low   = 'near low'
        position_near_high  = 'near high'
        position_weak       = 'weak'
        position_strong     = 'strong'
        position_neutral    = 'neutral'

        # Build-Summary narrative parts
        summary_pos_format  = 'Current spot sell rate {0} is at the {1}th percentile over the past 30 days, {2}.'
        summary_spot_only   = 'Current spot sell rate is {0}.'
        trend_rising        = 'SMA5 > SMA20. Short-term trend is rising.'
        trend_falling       = 'SMA5 < SMA20. Short-term trend is falling.'
        trend_consolidating = 'SMA5 ≈ SMA20. Short-term trend is consolidating.'
        rsi_format          = 'RSI={0}, {1}.'

        # RSI label
        rsi_overbought    = 'overbought'
        rsi_oversold      = 'oversold'
        rsi_label_neutral = 'neutral'

        # Trend labels
        trend_up          = 'rising'
        trend_down        = 'falling'
        trend_consolidate = 'consolidating'

        # ── 13. Get-RateRecommendation — Recommendations ───────────────────
        recommendation_buy_strong  = 'Strong Buy Recommended'
        recommendation_buy         = 'Buy Recommended'
        recommendation_hold        = 'Hold'
        recommendation_hold_sell   = 'Hold / Sell'
        recommendation_sell_strong = 'Strong Sell Recommended'

        # Cross-signal labels
        signal_bullish  = 'bullish'
        signal_bearish  = 'bearish'
        signal_diverged = 'diverged'
        strength_weak   = 'weak'
        strength_strong = 'strong'

        # Cross-signal list labels
        signal_rsi_bullish  = 'RSI bullish'
        signal_rsi_bearish  = 'RSI bearish'
        signal_sma_rising   = 'SMA rising'
        signal_sma_falling  = 'SMA falling'
        signal_macd_bullish = 'MACD bullish'
        signal_macd_bearish = 'MACD bearish'
        signal_bb_lower     = 'BB near lower band'
        signal_bb_upper     = 'BB near upper band'
        signal_pct_low      = 'percentile low'
        signal_pct_high     = 'percentile high'

        # Trend strength labels
        trend_strength_bull_strong  = 'Strong Bull'
        trend_strength_bull_weak    = 'Weak Bull'
        trend_strength_consolidate  = 'Consolidating'
        trend_strength_bear_weak    = 'Weak Bear'
        trend_strength_bear_strong  = 'Strong Bear'

        # Risk level labels
        risk_high   = 'High'
        risk_medium = 'Medium'
        risk_low    = 'Low'

        # Position percent descriptions
        pct_pos_low    = 'low'
        pct_pos_high   = 'high'
        pct_pos_middle = 'middle'

        # Bollinger position labels
        bb_near_lower = 'near lower band'
        bb_near_upper = 'near upper band'
        bb_middle     = 'mid-channel'

        # Bandwidth labels
        bw_high   = 'high volatility'
        bw_low    = 'low volatility'
        bw_normal = 'normal volatility'

        # MACD labels
        macd_bullish = 'bullish'
        macd_bearish = 'bearish'
        macd_neutral = 'neutral'

        # RSI score description
        rsi_score_overbought = 'strong'
        rsi_score_oversold   = 'weak'
        rsi_score_neutral    = 'neutral'

        # ── 14. DetailedReport Section Headers ──────────────────────────────
        report_header_line  = '═══════════════════════════════'
        report_header       = '  {0} FX Comprehensive Analysis — {1}'
        report_score_header = '📌 Overall Score: {0}  →  {1}'
        report_tech_header  = '  Technical Indicators'
        report_trend_header    = '📈 Trend Indicators'
        report_momentum_header = '📊 Momentum Indicators'
        report_volatility_header = '📐 Volatility Indicators'
        report_position_header   = '📏 Position Indicators'
        report_risk_header   = '  Trend Strength & Risk Assessment'
        report_cross_header  = '  Multi-Signal Consensus'
        report_rec_header    = '  Overall Recommendation'

        # Trend section
        sma_values       = '  SMA5: {0}  |  SMA20: {1}'
        sma_trend_format = '  Trend: {0} ({1} pts)'

        # Momentum section
        rsi_format_detail  = '  RSI(14): {0}  →  {1} ({2} pts)'
        macd_values        = '  MACD: {0}  |  Signal: {1}  |  Histogram: {2}'
        macd_judgement     = '  MACD Judgment: {0} ({1} pts)'

        # Volatility section
        bb_values        = '  Bollinger Bands: Upper {0}  |  Middle {1}  |  Lower {2}'
        percentb_format  = '  %B: {0}%  →  {1} ({2} pts)'
        bandwidth_format = '  Bandwidth: {0}%  →  {1} ({2} pts)'

        # Position section
        percentile_detail = '  30-Day Percentile: {0}%  →  Near {1} ({2} pts)'
        percentile_na     = '  30-Day Percentile: N/A'

        # Trend Strength & Risk section
        trend_strength_fmt = '📊 Trend Strength: {0}'
        trend_components   = '  (Combined SMA trend + MACD momentum + Bollinger Bandwidth)'
        risk_fmt           = '{0} Risk Level: {1}'
        risk_reason_bw     = 'High bandwidth ({0}%)'
        risk_reason_rsi    = 'RSI at extreme ({0})'
        risk_reason_normal = '  (All indicators within normal volatility and deviation ranges)'
        risk_reason_format = '  (Reason: {0})'

        # Cross-Signal section
        signal_diverged_fmt  = '⚖️ Bullish/Bearish signals diverged: {0} bullish / {1} bearish'
        signal_diverged_hint = '  Indicators have not reached consensus. Recommend wait-and-see.'
        signal_consensus_fmt = '{0} Multi-Signal Consensus: {1}{2}'
        signal_counts_fmt    = '  {0} bullish / {1} bearish signals'
        signal_list_fmt      = '  Consensus signals: {0}'
        signal_strong_bull   = '  ⮕ Multiple indicators agree on bullishness. Signal reliability is high. Consider adding positions.'
        signal_strong_bear   = '  ⮕ Multiple indicators agree on bearishness. Signal reliability is high. Exercise caution.'
        signal_weak_hint     = '  ⮕ Consensus is moderate. Wait for additional confirmation before acting.'

        # Consensus description labels (used in signal_consensus_fmt)
        consensus_desc_strong = '(Strong Consensus)'
        consensus_desc_weak   = '(Weak Consensus)'

        # Narrative recommendation
        rec_pos_near_low2    = 'Current {0} spot sell rate {1} is at the {2}th percentile over the past 30 days, near low.'
        rec_pos_near_high2   = 'Current {0} spot sell rate {1} is at the {2}th percentile over the past 30 days, near high.'
        rec_pos_low          = 'Current {0} spot sell rate {1} is at the {2}th percentile over the past 30 days, relatively low.'
        rec_pos_high         = 'Current {0} spot sell rate {1} is at the {2}th percentile over the past 30 days, relatively high.'
        rec_pos_neutral      = 'Current {0} spot sell rate {1} is at the {2}th percentile over the past 30 days, middle range.'
        rec_pos_other        = 'Current {0} spot sell rate {1} is at the {2}th percentile over the past 30 days, {3}.'
        rec_rsi_oversold     = 'RSI is {0}, in the oversold zone. Short-term rebound is possible.'
        rec_rsi_overbought   = 'RSI is {0}, in the overbought zone. Short-term pullback risk exists.'
        rec_rsi_neutral      = 'RSI is {0}, in the neutral zone.'
        rec_macd_positive    = 'MACD histogram turned positive. Momentum is strengthening.'
        rec_macd_negative    = 'MACD histogram remains negative. Momentum is weak.'
        rec_bb_near_lower    = 'Bollinger Bands %B is only {0}%. Price is near lower band support.'
        rec_bb_near_upper    = 'Bollinger Bands %B reached {0}%. Price is near upper band resistance.'
        rec_consensus_bull   = 'Multiple indicators form a bullish consensus. Signal reliability is increased.'
        rec_consensus_bear   = 'Multiple indicators form a bearish consensus. Signal reliability is increased.'
        rec_final_format     = 'Overall score {0} pts. {1}.'
        rec_suit_buy         = 'Suitable for those with foreign currency needs to buy in batches.'
        rec_suit_sell        = 'Consider delaying purchase, or consider selling in batches.'
        rec_suit_hold        = 'Continue observing and wait for clearer signals.'

        # Action Advice
        action_advice_header = '💡 Action Advice'
        action_bullet_format = '  • {0}'

        # Risk disclaimer
        risk_disclaimer = '⚠ This analysis is for reference only and does not constitute any investment advice. Please evaluate risks carefully before making any decisions.'

        # ── 15. Action Advice Strings ────────────────────────────────────────
        advice_rsi_oversold     = 'If RSI rebounds above 40, consider entering in batches'
        advice_rsi_overbought   = 'If RSI drops below 60, consider selling in batches'
        advice_rsi_weak_oversold = 'RSI is weak but not deeply oversold. Watch for further drop below 30 for a stronger buy signal'
        advice_rsi_weak_obought = 'RSI is strong but not deeply overbought. Watch for further break above 70 for a stronger sell signal'
        advice_sma_death_cross  = 'Watch for SMA5 crossing below SMA20 (death cross) as a trend reversal warning'
        advice_sma_golden_cross = 'Watch for SMA5 crossing above SMA20 (golden cross) as a trend reversal signal'
        advice_sma_near         = 'SMA5 and SMA20 are close. Watch for the upcoming directional breakout'
        advice_macd_bull_align  = 'MACD is in bullish alignment. If histogram shrinks, watch for momentum weakening'
        advice_macd_bear_align  = 'MACD is in bearish alignment. If histogram shrinks, watch for decline slowing'
        advice_bb_lower_break   = 'Price is near Bollinger lower band ({0}). If broken with expanding bandwidth, further decline may accelerate'
        advice_bb_upper_break   = 'Price is near Bollinger upper band ({0}). If broken with expanding bandwidth, may continue to strengthen'

        # ── 16. AI System Prompts ───────────────────────────────────────────
        ai_system_prompt_zh = @'
你是一位專業的外匯匯率分析師。請根據提供的統計指標進行分析，並給出簡潔的買入/賣出/觀望建議（3-5 句話），使用繁體中文回覆。

你的分析必須：
1. 引用具體數字（目前匯率、SMA 值、RSI、百分位數）來支持你的判斷
2. 提及目前匯率是否接近近期高點或低點
3. 結合 RSI 指標判斷超買或超賣狀態
4. 結合 SMA 均線判斷趨勢方向
5. 在建議末尾加上免責聲明：「以上分析僅供參考，不構成任何投資建議。投資有風險，請自行審慎評估。」
'@
        ai_system_prompt_en = @'
You are a professional foreign exchange rate analyst. Based on the provided statistical indicators, analyze the FX data and provide a concise buy/sell/hold recommendation (3-5 sentences), responding in English.

Your analysis must:
1. Cite specific numbers (current rate, SMA values, RSI, percentile) to support your judgment
2. Note whether the current rate is near recent highs or lows
3. Use the RSI indicator to determine overbought or oversold conditions
4. Use the SMA moving averages to determine trend direction
5. End with a disclaimer: ''This analysis is for reference only and does not constitute any investment advice. Please evaluate risks carefully before making any decisions.''

When responding, prioritize English output. Use the same key indicator labels as provided (SMA5, SMA20, RSI14, etc.).
'@
    }
}

# Map: Period ID → L() key for display text
$script:PeriodMap = [ordered]@{
    today = 'period_today'
    '1m'  = 'period_1m'
    '3m'  = 'period_3m'
    '6m'  = 'period_6m'
    '1y'  = 'period_1y'
    '3y'  = 'period_3y'
    '5y'  = 'period_5y'
    '10y' = 'period_10y'
}

# Current language (default: zh)
$script:CurrentLang = 'zh'

# -----------------------------------------------------------------------------
# Function: L — Translate a key, optionally with format arguments
# -----------------------------------------------------------------------------

function L {
    <#
    .SYNOPSIS
        Translates a localization key to the current language string.
    .DESCRIPTION
        Looks up $Key in $script:Lang[$script:CurrentLang].
        If $FmtArgs are provided, uses -f to format the string.
        Falls back to the key name if not found.
    .PARAMETER Key
        The localization key string.
    .PARAMETER FmtArgs
        Optional format arguments passed to -f.
    .OUTPUTS
        [string] The translated (and optionally formatted) string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Key,

        [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
        [object[]]$FmtArgs
    )

    $langBlock = $script:Lang[$script:CurrentLang]
    if ($null -eq $langBlock) {
        if ($FmtArgs.Count -gt 0) { return $Key -f $FmtArgs } else { return $Key }
    }

    $template = $langBlock[$Key]
    if ($null -eq $template) {
        if ($FmtArgs.Count -gt 0) { return $Key -f $FmtArgs } else { return $Key }
    }

    if ($FmtArgs.Count -gt 0) {
        try {
            return $template -f $FmtArgs
        }
        catch {
            return $template
        }
    }

    return $template
}

# -----------------------------------------------------------------------------
# Function: Set-Language
# -----------------------------------------------------------------------------

function Set-Language {
    <#
    .SYNOPSIS
        Sets the active language for the i18n module.
    .PARAMETER Lang
        Language code: 'zh' (Traditional Chinese, default) or 'en' (English).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('zh', 'en')]
        [string]$Lang
    )

    $script:CurrentLang = $Lang
}

# -----------------------------------------------------------------------------
# Function: Get-Language
# -----------------------------------------------------------------------------

function Get-Language {
    <#
    .SYNOPSIS
        Returns the currently active language code.
    .OUTPUTS
        [string] 'zh' or 'en'.
    #>
    return $script:CurrentLang
}

# -----------------------------------------------------------------------------
# Function: Get-PeriodDisplay
# -----------------------------------------------------------------------------

function Get-PeriodDisplay {
    <#
    .SYNOPSIS
        Returns the localized display text for a period ID.
    .PARAMETER PeriodId
        Period identifier: today, 1m, 3m, 6m, 1y, 3y, 5y, 10y.
    .OUTPUTS
        [string] Display text in the current language (e.g. '本日' or 'Today').
        Returns $PeriodId if not found.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PeriodId
    )

    $key = $script:PeriodMap[$PeriodId]
    if ($null -ne $key) {
        return L $key
    }
    return $PeriodId
}

# -----------------------------------------------------------------------------
# Function: Get-CurrencyNameEn
# -----------------------------------------------------------------------------

function Get-CurrencyNameEn {
    <#
    .SYNOPSIS
        Returns the English name of a currency by its 3-letter code.
    .PARAMETER Code
        The 3-letter ISO currency code (e.g. 'USD', 'JPY').
    .OUTPUTS
        [string] English currency name (e.g. 'US Dollar', 'Japanese Yen').
        Returns the code itself if not found.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Code
    )

    $key = "currency_$($Code.ToLower())_en"
    $langBlock = $script:Lang[$script:CurrentLang]
    if ($null -ne $langBlock) {
        $result = $langBlock[$key]
        if ($null -ne $result) {
            return $result
        }
    }
    return $Code
}

# -----------------------------------------------------------------------------
# Module Exports
# -----------------------------------------------------------------------------
Export-ModuleMember -Function @(
    'L',
    'Set-Language',
    'Get-Language',
    'Get-PeriodDisplay',
    'Get-CurrencyNameEn'
)