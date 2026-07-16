import type { ReactNode } from "react";

interface Props {
  children: ReactNode;
  tone?: "cyan" | "green" | "neutral" | "pink" | "warning";
}

export function StatusBadge({ children, tone = "neutral" }: Props) {
  return <span className={`status-badge status-badge--${tone}`}>{children}</span>;
}
