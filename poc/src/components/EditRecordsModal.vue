<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition-opacity duration-300"
      enter-from-class="opacity-0"
      leave-active-class="transition-opacity duration-300"
      leave-to-class="opacity-0"
    >
      <div
        v-if="open"
        class="fixed inset-0 bg-black/40 backdrop-blur-sm flex items-center justify-center z-50"
        @click.self="$emit('close')"
      >
        <div class="bg-white rounded-2xl shadow-md w-full max-w-md p-8 font-sans text-gray-800">
          <h2 class="text-xl font-semibold mb-4">Edit Profile Records</h2>

          <div class="space-y-4">
            <div>
              <label class="block text-sm text-gray-700 mb-1">Twitter Handle</label>
              <input
                v-model="local.twitter"
                type="text"
                placeholder="username"
                :class="[
                  'w-full border rounded-lg px-3 py-2 focus:ring-2 focus:ring-[#E6007A]/30',
                  errors.twitter ? 'border-red-500' : 'border-gray-300',
                ]"
              />
              <p v-if="errors.twitter" class="text-red-500 text-xs mt-1">{{ errors.twitter }}</p>
            </div>

            <div>
              <label class="block text-sm text-gray-700 mb-1">GitHub Handle</label>
              <input
                v-model="local.github"
                type="text"
                placeholder="username"
                :class="[
                  'w-full border rounded-lg px-3 py-2 focus:ring-2 focus:ring-[#E6007A]/30',
                  errors.github ? 'border-red-500' : 'border-gray-300',
                ]"
              />
              <p v-if="errors.github" class="text-red-500 text-xs mt-1">{{ errors.github }}</p>
            </div>

            <div>
              <label class="block text-sm text-gray-700 mb-1">Description</label>
              <textarea
                v-model="local.description"
                rows="3"
                maxlength="200"
                placeholder="Tell us about yourself..."
                :class="[
                  'w-full border rounded-lg px-3 py-2 focus:ring-2 focus:ring-[#E6007A]/30',
                  errors.description ? 'border-red-500' : 'border-gray-300',
                ]"
              ></textarea>
              <p v-if="errors.description" class="text-red-500 text-xs mt-1">
                {{ errors.description }}
              </p>
              <p v-else class="text-gray-500 text-xs mt-1">
                {{ local.description.length }}/200 characters
              </p>
            </div>

            <div>
              <label class="block text-sm text-gray-700 mb-1">Personal Website</label>
              <input
                v-model="local.url"
                type="text"
                placeholder="https://example.com"
                :class="[
                  'w-full border rounded-lg px-3 py-2 focus:ring-2 focus:ring-[#E6007A]/30',
                  errors.url ? 'border-red-500' : 'border-gray-300',
                ]"
              />
              <p v-if="errors.url" class="text-red-500 text-xs mt-1">{{ errors.url }}</p>
            </div>
          </div>

          <div class="flex justify-between mt-8">
            <button
              @click="$emit('close')"
              class="px-4 py-2 rounded-lg border border-gray-300 hover:bg-gray-100 transition"
            >
              Cancel
            </button>

            <button
              @click="handleSave"
              :disabled="!canSave"
              :class="[
                'px-4 py-2 rounded-lg text-white transition',
                canSave ? 'bg-[#E6007A] hover:bg-[#d1006f]' : 'bg-gray-300 cursor-not-allowed',
              ]"
            >
              Save
            </button>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup lang="ts">
import { ref, watch, computed } from 'vue';

interface Props {
  open: boolean;
  twitter: string | null;
  github: string | null;
  description: string | null;
  url: string | null;
  name: string;
}

const props = defineProps<Props>();
const emit = defineEmits(['close', 'save']);

const local = ref({
  twitter: props.twitter ?? '',
  github: props.github ?? '',
  description: props.description ?? '',
  url: props.url ?? '',
});

const errors = ref({
  twitter: '',
  github: '',
  description: '',
  url: '',
});

watch(
  () => props.open,
  v => {
    if (v) {
      local.value = {
        twitter: props.twitter ?? '',
        github: props.github ?? '',
        description: props.description ?? '',
        url: props.url ?? '',
      };
      clearErrors();
    }
  }
);

function clearErrors() {
  errors.value.twitter = '';
  errors.value.github = '';
  errors.value.description = '';
  errors.value.url = '';
}

function validate() {
  clearErrors();

  if (local.value.twitter && !/^[A-Za-z0-9_]{1,15}$/.test(local.value.twitter)) {
    errors.value.twitter =
      'Invalid Twitter handle (alphanumeric and underscore, max 15 characters)';
  }

  if (local.value.github) {
    const gh = local.value.github;
    if (gh.length > 39) {
      errors.value.github = 'GitHub handle must be 39 characters or less';
    } else if (!/^[a-zA-Z0-9]/.test(gh) || !/[a-zA-Z0-9]$/.test(gh)) {
      errors.value.github = 'GitHub handle cannot start or end with a hyphen';
    } else if (/--/.test(gh)) {
      errors.value.github = 'GitHub handle cannot contain consecutive hyphens';
    } else if (!/^[a-zA-Z0-9-]+$/.test(gh)) {
      errors.value.github = 'GitHub handle may only contain alphanumeric characters or hyphens';
    }
  }

  if (local.value.description) {
    if (local.value.description.length < 10) {
      errors.value.description = 'Description must be at least 10 characters';
    } else if (local.value.description.length > 200) {
      errors.value.description = 'Description must be 200 characters or less';
    }
  }

  if (local.value.url && !/^https?:\/\/.+\..+/.test(local.value.url)) {
    errors.value.url = 'URL must be a valid web address starting with http:// or https://';
  }
}

const canSave = computed(() => {
  validate();
  return (
    !errors.value.twitter && !errors.value.github && !errors.value.description && !errors.value.url
  );
});

function handleSave() {
  if (!canSave.value) return;
  emit('save', { ...local.value });
}
</script>
