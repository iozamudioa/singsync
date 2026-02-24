package net.iozamudioa.singsync

object SnapshotShareBridge {
	@Volatile
	private var pendingSavedFeedback: Boolean = false

	fun markSavedFeedback() {
		pendingSavedFeedback = true
	}

	fun consumeSavedFeedback(): Boolean {
		if (!pendingSavedFeedback) {
			return false
		}
		pendingSavedFeedback = false
		return true
	}
}
