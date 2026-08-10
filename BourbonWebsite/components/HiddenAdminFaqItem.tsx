"use client";

import { useRef } from "react";
import { useRouter } from "next/navigation";

const REQUIRED_CLICKS = 5;
const CLICK_WINDOW_MS = 2_000;

type HiddenAdminFaqItemProps = { question: string; answer: string };

export function HiddenAdminFaqItem({
  question,
  answer
}: HiddenAdminFaqItemProps) {
  const router = useRouter();
  const clickState = useRef({ count: 0, startedAt: 0 });

  function recordClick() {
    const now = Date.now();
    const state = clickState.current;
    if (now - state.startedAt > CLICK_WINDOW_MS) {
      state.count = 0;
      state.startedAt = now;
    }
    if (state.count === 0) state.startedAt = now;
    state.count += 1;
    if (state.count === REQUIRED_CLICKS) {
      state.count = 0;
      state.startedAt = 0;
      router.push("/admin/login");
    }
  }

  return (
    <section onClick={recordClick}>
      <h2>{question}</h2>
      <p>{answer}</p>
    </section>
  );
}
