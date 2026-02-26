<script setup>
import { RouterView } from 'vue-router'
</script>

<template>
  <v-app>
    <v-locale-provider rtl>
      <RouterView />
    </v-locale-provider>
  </v-app>
</template>
