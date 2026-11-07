<script setup lang="ts">
import { onMounted, useTemplateRef } from "vue"

const emit = defineEmits<{ close: [] }>()

const dialog = useTemplateRef<HTMLDialogElement>("dialog")

onMounted(() => dialog.value?.showModal())
</script>

<template>
  <dialog ref="dialog" class="modal" @cancel.prevent="emit('close')" @close="emit('close')">
    <div class="modal-box text-base-content">
      <slot />
    </div>
  </dialog>
</template>
