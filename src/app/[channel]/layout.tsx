import { type ReactNode } from "react";

export const dynamic = 'force-dynamic';
export const dynamicParams = true;

export default function ChannelLayout({ children }: { children: ReactNode }) {
	return children;
}
