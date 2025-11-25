import { createRouter, createWebHistory } from 'vue-router';
import LandingView from '../views/LandingView.vue';
import ProfileView from '../views/ProfileView.vue';
import ReverseResolver from '../views/ReverseResolver.vue';
import WhoProfileView from '../views/WhoProfileView.vue';

const routes = [
  { path: '/', name: 'Home', component: LandingView },
  { path: '/profile', name: 'Profile', component: ProfileView },
  { path: '/lookup', name: 'Lookup', component: ReverseResolver },

  {
    path: '/whois/:name',
    name: 'Whois',
    component: WhoProfileView,
    props: true,
  },
];

const router = createRouter({
  history: createWebHistory(),
  routes,
});

const navigationEntries = performance?.getEntriesByType(
  'navigation'
) as PerformanceNavigationTiming[];
const isReload =
  navigationEntries.length > 0 && navigationEntries[0] && navigationEntries[0].type === 'reload';

router.isReady().then(() => {
  if (isReload && location.pathname !== '/') {
    router.replace('/');
  }
});

export default router;
