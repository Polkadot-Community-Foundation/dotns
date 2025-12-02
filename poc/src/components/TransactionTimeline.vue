<template>
  <div v-if="transactionStatus !== 'idle'" class="tx-container">
    <div class="tx-progress">
      <div v-for="(step, index) in steps" :key="step.key" class="tx-node">
        <div
          class="tx-dot"
          :class="{
            active: transactionStatus === step.key,
            done: isCompleted(step.key),
          }"
        ></div>

        <div
          v-if="index < steps.length - 1"
          class="tx-line"
          :class="{
            done: isCompleted(step.key),
            activeLine: transactionStatus === step.key,
          }"
        ></div>
      </div>
    </div>

    <div class="tx-labels">
      <span
        v-for="step in steps"
        :key="step.key"
        :class="{
          activeLabel: transactionStatus === step.key,
          completedLabel: isCompleted(step.key),
        }"
      >
        {{ step.label }}
      </span>
    </div>
  </div>
</template>

<script setup>
import { storeToRefs } from 'pinia';
import { useWalletStore } from '../store/useWalletStore';

const walletStore = useWalletStore();
const { transactionStatus } = storeToRefs(walletStore);

const steps = [
  { key: 'signing', label: 'Signing' },
  { key: 'broadcasting', label: 'Broadcast' },
  { key: 'included', label: 'Included' },
  { key: 'finalized', label: 'Finalized' },
];

function isCompleted(stepKey) {
  const order = ['signing', 'broadcasting', 'included', 'finalized'];
  return order.indexOf(transactionStatus.value) > order.indexOf(stepKey);
}
</script>

<style scoped>
.tx-container {
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  padding: 6px 0 4px;
  background: rgba(255, 255, 255, 0.9);
  backdrop-filter: blur(6px);
  -webkit-backdrop-filter: blur(6px);
  z-index: 999999;
  display: flex;
  flex-direction: column;
  align-items: center;
}

.tx-progress {
  display: flex;
  align-items: center;
  justify-content: space-between;
  width: min(90%, 900px);
}

.tx-node {
  display: flex;
  align-items: center;
}

.tx-dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: #cfcfcf;
  transition: all 0.25s ease;
}

.tx-dot.active {
  background: #e6007a;
  transform: scale(1.6);
  animation: pulseDot 1.2s infinite ease-in-out;
}

.tx-dot.done {
  background: #16c172;
}

@keyframes pulseDot {
  0% {
    transform: scale(1.4);
  }
  50% {
    transform: scale(1.8);
  }
  100% {
    transform: scale(1.4);
  }
}

.tx-line {
  width: min(26vw, 140px);
  height: 3px;
  background: #dcdcdc;
  margin: 0 6px;
  position: relative;
  overflow: hidden;
  border-radius: 2px;
}

.tx-line.done {
  background: #16c172;
}

.tx-line.activeLine::after {
  content: '';
  position: absolute;
  top: 0;
  left: -50%;
  width: 50%;
  height: 100%;
  background: #e6007a;
  animation: moveHighlight 1.5s infinite linear;
}

@keyframes moveHighlight {
  0% {
    left: -50%;
  }
  100% {
    left: 100%;
  }
}

.tx-labels {
  margin-top: 3px;
  width: min(90%, 900px);
  display: flex;
  justify-content: space-between;
  font-size: 12px;
  opacity: 0.9;
}

.activeLabel {
  font-weight: 600;
  color: #e6007a;
}

.completedLabel {
  color: #16c172;
}
</style>
