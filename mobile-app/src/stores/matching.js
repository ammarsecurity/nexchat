import { defineStore } from 'pinia'
import { ref } from 'vue'

export const useMatchingStore = defineStore('matching', () => {
  const status = ref('idle') // idle | searching | matched
  const genderFilter = ref('all') // all | male | female

  function setSearching() { status.value = 'searching' }
  function setMatched() { status.value = 'matched' }
  function setIdle() { status.value = 'idle' }

  return { status, genderFilter, setSearching, setMatched, setIdle }
})
