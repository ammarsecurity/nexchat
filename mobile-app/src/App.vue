<script setup>
import { RouterView } from 'vue-router'
</script>

<template>
  <div id="app-root">
    <RouterView v-slot="{ Component }">
      <Transition name="page" mode="out-in">
        <component :is="Component" />
      </Transition>
    </RouterView>
  </div>
</template>

<style>
#app-root {
  height: 100%;
  width: 100%;
  position: relative;
  overflow: hidden;
}
</style>
