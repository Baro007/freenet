package com.freenet.vpn

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.concurrent.CopyOnWriteArrayList

object LogManager {
    private val _logs = CopyOnWriteArrayList<String>()
    
    private val _logsFlow = MutableStateFlow<List<String>>(emptyList())
    val logsFlow: StateFlow<List<String>> = _logsFlow.asStateFlow()

    private const val MAX_LOGS = 200

    fun log(message: String) {
        val clean = message.trim()
        if (clean.isEmpty()) return
        
        _logs.add(clean)
        if (_logs.size > MAX_LOGS) {
            _logs.removeAt(0)
        }
        _logsFlow.value = _logs.toList()
    }

    fun clear() {
        _logs.clear()
        _logsFlow.value = emptyList()
    }
}
