<script setup>
import { RouterView } from 'vue-router'
import AppNotify from './components/AppNotify.vue'
</script>

<template>
  <v-app>
    <v-locale-provider rtl>
      <RouterView />
      <AppNotify />
    </v-locale-provider>
  </v-app>
</template>
