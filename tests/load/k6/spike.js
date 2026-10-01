import { userFlow } from './scenario.js';

export const options = {
  scenarios: {
    spike: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '5m', target: 50 },
        { duration: '30s', target: 200 },
        { duration: '5m', target: 200 },
        { duration: '30s', target: 500 },
        { duration: '5m', target: 500 },
        { duration: '30s', target: 50 },
        { duration: '10m', target: 50 },
        { duration: '2m', target: 0 },
      ],
    },
  },
  thresholds: { http_req_duration: ['p(99)<1500'] },
};

export default function () { userFlow(); }
