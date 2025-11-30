/// SharedPreferences key constants for SettingsProvider
///
/// All keys follow the pattern: domain_setting_name_v1
/// The v1 suffix allows for future migrations if needed
abstract class SettingsKeys {
  // Provider management
  static const String providersOrder = 'providers_order_v1';
  static const String providerConfigs = 'provider_configs_v1';
  static const String pinnedModels = 'pinned_models_v1';
  static const String selectedModel = 'selected_model_v1';
  static const String lastSelectedProviderTab = 'last_selected_provider_tab_v1';

  // Theme & appearance
  static const String themeMode = 'theme_mode_v1';
  static const String themePalette = 'theme_palette_v1';
  static const String useDynamicColor = 'use_dynamic_color_v1';
  static const String usePureBackground = 'display_use_pure_background_v1';
  static const String chatMessageBackgroundStyle = 'display_chat_message_background_style_v1';
  static const String chatBubbleOpacity = 'display_chat_bubble_opacity_v1';

  // Model configurations
  static const String titleModel = 'title_model_v1';
  static const String titlePrompt = 'title_prompt_v1';
  static const String translateModel = 'translate_model_v1';
  static const String translatePrompt = 'translate_prompt_v1';
  static const String ocrModel = 'ocr_model_v1';
  static const String ocrPrompt = 'ocr_prompt_v1';
  static const String ocrEnabled = 'ocr_enabled_v1';
  static const String thinkingBudget = 'thinking_budget_v1';

  // Display: message visibility
  static const String displayShowUserAvatar = 'display_show_user_avatar_v1';
  static const String displayShowModelIcon = 'display_show_model_icon_v1';
  static const String displayShowModelNameTimestamp = 'display_show_model_name_timestamp_v1';
  static const String displayShowTokenStats = 'display_show_token_stats_v1';
  static const String displayShowUserNameTimestamp = 'display_show_user_name_timestamp_v1';
  static const String displayShowUserMessageActions = 'display_show_user_message_actions_v1';
  static const String displayAutoCollapseThinking = 'display_auto_collapse_thinking_v1';
  static const String displayShowMessageNav = 'display_show_message_nav_v1';
  static const String displayShowChatListDate = 'display_show_chat_list_date_v1';
  static const String displayShowAppUpdates = 'display_show_app_updates_v1';
  static const String displayNewChatOnLaunch = 'display_new_chat_on_launch_v1';

  // Display: haptics
  static const String displayHapticsOnGenerate = 'display_haptics_on_generate_v1';
  static const String displayHapticsOnDrawer = 'display_haptics_on_drawer_v1';
  static const String displayHapticsGlobalEnabled = 'display_haptics_global_enabled_v1';
  static const String displayHapticsIosSwitch = 'display_haptics_ios_switch_v1';
  static const String displayHapticsOnListItemTap = 'display_haptics_on_list_item_tap_v1';
  static const String displayHapticsOnCardTap = 'display_haptics_on_card_tap_v1';

  // Display: fonts & scaling
  static const String displayChatFontScale = 'display_chat_font_scale_v1';
  static const String displayAppFontFamily = 'display_app_font_family_v1';
  static const String displayAppFontIsGoogle = 'display_app_font_is_google_v1';
  static const String displayCodeFontFamily = 'display_code_font_family_v1';
  static const String displayCodeFontIsGoogle = 'display_code_font_is_google_v1';
  static const String displayAppFontLocalPath = 'display_app_font_local_path_v1';
  static const String displayAppFontLocalAlias = 'display_app_font_local_alias_v1';
  static const String displayCodeFontLocalPath = 'display_code_font_local_path_v1';
  static const String displayCodeFontLocalAlias = 'display_code_font_local_alias_v1';

  // Display: scrolling behavior
  static const String displayAutoScrollIdleSeconds = 'display_auto_scroll_idle_seconds_v1';
  static const String displayDisableAutoScroll = 'display_disable_auto_scroll_v1';
  static const String displayChatBackgroundMaskStrength = 'display_chat_background_mask_strength_v1';

  // Display: markdown & math rendering
  static const String displayEnableDollarLatex = 'display_enable_dollar_latex_v1';
  static const String displayEnableMathRendering = 'display_enable_math_rendering_v1';
  static const String displayEnableUserMarkdown = 'display_enable_user_markdown_v1';
  static const String displayEnableReasoningMarkdown = 'display_enable_reasoning_markdown_v1';

  // Desktop UI
  static const String displayDesktopWideContent = 'display_desktop_wide_content_v1';
  static const String displayDesktopNarrowWidth = 'display_desktop_narrow_width_v1';
  static const String displayDesktopAutoSwitchTopics = 'display_desktop_auto_switch_topics_v1';
  static const String desktopSidebarWidth = 'desktop_sidebar_width_v1';
  static const String desktopSidebarOpen = 'desktop_sidebar_open_v1';
  static const String desktopTopicPosition = 'desktop_topic_position_v1';
  static const String desktopRightSidebarOpen = 'desktop_right_sidebar_open_v1';
  static const String desktopRightSidebarWidth = 'desktop_right_sidebar_width_v1';
  static const String desktopSettingsSidebarWidth = 'desktop_settings_sidebar_width_v1';
  static const String desktopGlobalFontScale = 'desktop_global_font_scale_v1';
  static const String desktopSelectedSettingsMenu = 'desktop_selected_settings_menu_v1';
  static const String desktopCloseToTray = 'desktop_close_to_tray_v1';

  // Locale
  static const String appLocale = 'app_locale_v1';

  // Learning mode
  static const String learningModeEnabled = 'learning_mode_enabled_v1';
  static const String learningModePrompt = 'learning_mode_prompt_v1';

  // Search
  static const String searchServices = 'search_services_v1';
  static const String searchCommon = 'search_common_v1';
  static const String searchSelected = 'search_selected_v1';
  static const String searchEnabled = 'search_enabled_v1';

  // Sticker
  static const String stickerEnabled = 'sticker_enabled_v1';
  static const String showStickerToolUI = 'show_sticker_tool_ui_v1';

  // Backup
  static const String webDavConfig = 'webdav_config_v1';

  // Android specific
  static const String androidBackgroundChatMode = 'android_background_chat_mode_v1';
}
