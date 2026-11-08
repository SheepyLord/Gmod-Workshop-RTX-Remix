"""The naming rule for characters, their packs and their records (the user, 2026-11-08).

A model's recorded name is the character's own name, as the user uses it: Chisa, Guinaifen, Alf,
March 7th. It carries no game or franchise tag (鸣潮, 星穹铁道, 原神, HSR, WuWa, Genshin,
[Arknights]), no version, build or edition tag (2.0, v1.2, Ver.3, 合体7), no author or uploader tag
(by_mobius, Tda式) and no rating or format tag (R18, NSFW, MMD, PMX). The rule covers Model
Hotloader display names, the <n> of mmdhl_<n>, pbr_<n> and <n>-rtx, titles, bodygroup preset names
and the names written into records (mod.usda doc strings, package READMEs, descriptions).

    find(text, kind)              the reasons text breaks the rule; an empty list when it is clean
    refusal(label, text, kind)    one line for stderr, or None

Kinds:
    "name"   a display name or an item name: every tag below, and pack words (RTX, PBR, Remix,
             Hotloader, Workshop, pack, model) as well
    "title"  a title, a label or a record's text: every tag below
    "slug"   a folder name or package id (mmdhl_robin, pbr_evernight_march7th, chisa-rtx): the
             mmdhl_ / pbr_ prefix and the -rtx suffix are left out, separators read as spaces
    "prose"  a description: game and franchise tags only (it may name loader versions)

Standard library only. Two identical copies exist, in workshop-content-pack/scripts and
mmd-remix-pbr/scripts, so each skill runs alone; test_names.py checks that they match.
"""
from __future__ import annotations

import re
import unicodedata

# Games and franchises as they appear in model, folder and package names. Add a game here (and a
# case to test_names.py) when a character from a new one turns up.
GAMES_CJK = (
    "鸣潮", "鳴潮",                                    # Wuthering Waves
    "星穹铁道", "星穹鐵道", "スターレイル",              # Honkai: Star Rail
    "崩坏", "崩壞", "崩壊",                             # Honkai (Star Rail, Impact 3rd)
    "原神",                                            # Genshin Impact
    "明日方舟", "アークナイツ",                          # Arknights
    "终末地", "終末地", "エンドフィールド",               # Arknights: Endfield
    "绝区零", "絕區零", "ゼンレスゾーンゼロ",             # Zenless Zone Zero
    "白银之城", "白銀之城",                              # Silver Palace
    "异环", "異環",                                     # Neverness to Everness
    "碧蓝航线", "碧藍航線", "アズールレーン",             # Azur Lane
    "蔚蓝档案", "蔚藍檔案", "碧蓝档案", "ブルーアーカイブ",  # Blue Archive
    "少女前线", "少女前線",                              # Girls' Frontline
    "战双帕弥什", "戰雙帕彌什",                          # Punishing: Gray Raven
    "幻塔",                                            # Tower of Fantasy
    "尘白禁区", "塵白禁區",                              # Snowbreak
    "胜利女神", "勝利女神", "勝利の女神",                 # NIKKE
)
GAMES_LATIN = (
    "wuthering waves", "wuwa", "honkai", "star rail", "hsr", "hi3", "genshin", "arknights",
    "endfield", "zenless", "zzz", "silver palace", "neverness to everness", "nte", "azur lane",
    "blue archive", "girls frontline", "gfl", "punishing gray raven", "pgr", "tower of fantasy",
    "snowbreak", "nikke",
)
FORMAT_WORDS = ("mmd", "pmx", "pmd", "nsfw")
PACK_WORDS = ("rtx", "pbr", "remix", "hotloader", "workshop", "pack", "package", "model", "addon")

R18 = re.compile(r"(?<![a-z0-9])r\s*-?\s*18(?![0-9])|(?<![0-9])18\s*\+")
# Where a pattern needs a character before the tag, group 1 is the tag itself.
VERSIONS = (
    re.compile(r"\d+(?:\.\d+)+"),                                  # 2.0, 1.0.3
    re.compile(r"(?<![a-z])v(?:er(?:sion)?)?\s*\.?\s*\d+"),        # v1, ver.3, version 2, V4X
    re.compile(r"合[体體]\s*\d+"),                                 # 合体7
    re.compile(r"\d+\s*版|版本|第\s*\S{1,3}\s*[版代弾弹期]|周年"),    # 2版, 版本, 第二版, 三周年
    re.compile(r"[^\x00-\x7f]\s*(\d+)\s*$"),                       # 千咲2: an edition number after a name
    re.compile(r"[a-z]\s+(\d+)\s*$"),                              # Robin 2
)
SLUG_VERSION = re.compile(r"(?<![a-z0-9])\d+ \d+(?![a-z0-9])")     # alf_2_0: 2.0 written into a slug
AUTHORS = (
    re.compile(r"(?<![a-z])by(?![a-z])"),                          # by_mobius, 1.0by mobius, By Alicia
    re.compile(r"@"),
    re.compile(r"作者|配布|改模|模型|制作|製作|改変"),
    re.compile(r"([a-z0-9]+式)"),                                  # Tda式
)
BRACKETS = re.compile(r"[\[【〔《「『〖〘][^\]】〕》」』〗〙]*[\]】〕》」』〗〙]?")
# Two non-ASCII runs joined by a dash or an underscore: a "<game>-<name>" folder (鸣潮-千咲).
# The Japanese long-vowel mark (ー) and the middle dot (阮·梅) are not separators.
FOLDER_FORM = re.compile(r"[^\x00-\x7f]\s*[-‐‑‒–—―−_]\s*[^\x00-\x7f]")
KINDS = ("name", "title", "slug", "prose")


def _fold(text: str) -> str:
    return unicodedata.normalize("NFKC", text or "").casefold()


def _latin(folded: str) -> str:
    return " " + re.sub(r"[^a-z0-9]+", " ", folded) + " "


def _words(latin: str, words) -> list:
    return [w for w in words if " " + re.sub(r"[^a-z0-9]+", " ", w).strip() + " " in latin]


def _tag(match) -> str:
    return (match.group(1) if match.re.groups else match.group(0)).strip()


def find(text: str, kind: str = "name") -> list:
    """The reasons `text` breaks the naming rule, each a short phrase; empty when it is clean."""
    if kind not in KINDS:
        raise ValueError("kind must be one of %s" % ", ".join(KINDS))
    folded = _fold(text)
    if kind == "slug":
        folded = re.sub(r"^(mmdhl|pbr)_", "", folded)
        folded = re.sub(r"[-_]rtx$", "", folded)
    latin = _latin(folded)
    found = []
    for tag in GAMES_CJK:
        if tag in folded:
            found.append("game tag %r" % tag)
    for tag in _words(latin, GAMES_LATIN):
        found.append("game tag %r" % tag)
    if kind == "prose":
        return found
    match = R18.search(folded)
    if match:
        found.append("rating tag %r" % match.group(0).strip())
    for tag in _words(latin, FORMAT_WORDS):
        found.append("rating or format tag %r" % tag)
    if kind == "name":
        for tag in _words(latin, PACK_WORDS):
            found.append("pack word %r" % tag)
    spaced = latin.strip() if kind == "slug" else folded
    for pattern in VERSIONS:
        match = pattern.search(spaced)
        if match:
            found.append("version or edition tag %r" % _tag(match))
            break
    if kind == "slug":
        match = SLUG_VERSION.search(spaced)
        if match and not any(f.startswith("version") for f in found):
            found.append("version tag %r" % match.group(0).replace(" ", "_"))
    for pattern in AUTHORS:
        match = pattern.search(spaced)
        if match:
            found.append("author tag %r" % _tag(match))
            break
    match = BRACKETS.search(folded)
    if match:
        found.append("bracketed tag %r" % match.group(0))
    match = FOLDER_FORM.search(unicodedata.normalize("NFKC", text or ""))
    if match:
        found.append("<prefix>-<name> folder form %r" % match.group(0))
    return found


def refusal(label: str, text: str, kind: str = "name"):
    """One line saying why `text` (the value of `label`) is refused, or None when it is clean."""
    reasons = find(text, kind)
    if not reasons:
        return None
    return ("%s %r carries %s: give the character's own name only, with no game, version, author, "
            "rating or pack tag (Chisa, not 鸣潮-千咲; Alf, not 阿芙2.0; see model_names.py.md)"
            % (label, text, "; ".join(reasons)))
