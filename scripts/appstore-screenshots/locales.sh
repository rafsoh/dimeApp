# App Store locales with screenshots, and the app language, region and currency each is captured in.
# es-MX and fr-CA reuse the es-ES and fr-FR screenshots (see generate.sh).
ALL_LOCALES=(en-GB de-DE es-ES fr-FR it ja ko nl-NL pt-BR ru tr zh-Hans zh-Hant)

locale_settings() {
  case "$1" in
    en-GB) echo "en en_US USD" ;;
    de-DE) echo "de de_DE EUR" ;;
    es-ES) echo "es es_ES EUR" ;;
    fr-FR) echo "fr fr_FR EUR" ;;
    it) echo "it it_IT EUR" ;;
    ja) echo "ja ja_JP JPY" ;;
    ko) echo "ko ko_KR KRW" ;;
    nl-NL) echo "nl nl_NL EUR" ;;
    pt-BR) echo "pt-BR pt_BR BRL" ;;
    ru) echo "ru ru_RU RUB" ;;
    tr) echo "tr tr_TR TRY" ;;
    zh-Hans) echo "zh-Hans zh_CN CNY" ;;
    zh-Hant) echo "zh-Hant zh_TW TWD" ;;
    *) echo "Unknown locale: $1" >&2; return 1 ;;
  esac
}
