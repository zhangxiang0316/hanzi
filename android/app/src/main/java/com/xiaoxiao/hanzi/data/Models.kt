package com.xiaoxiao.hanzi.data

import android.content.Context
import org.json.JSONObject

/** 一个字的学习元数据（对应小程序 data/meta.js 的一项） */
class CharMeta(
    val ch: String,
    val py: String,
    val words: List<Word>,
    val radical: String,
    val strokes: Int,
    val book: String,
    val lesson: String,
    val writeLesson: String,
    /** 多音字读音表；单音字为 null */
    val readings: List<Reading>?
)

class Word(val word: String, val pinyin: String)

class Reading(val pinyin: String, val lesson: String)

class Lesson(
    val id: String,
    val book: String,
    val unit: Int,
    val no: Int,
    val title: String,
    val kind: String,
    val page: Int,
    val chars: List<String>,
    val write: List<String>,
    val words: List<String>
)

class Unit(val no: Int, val title: String, val theme: String, val lessons: List<String>)

class BookStat(val chars: Int, val write: Int, val lessons: Int, val units: Int)

class Book(
    val id: String,
    val name: String,
    val short: String,
    val grade: Int,
    val term: Int,
    val units: List<Unit>,
    val lessons: List<String>,
    val stat: BookStat
)
