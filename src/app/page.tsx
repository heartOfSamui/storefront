import { redirect } from "next/navigation";

export const dynamic = 'force-dynamic';

export default function EmptyPage() {
	const defaultChannel = process.env.NEXT_PUBLIC_DEFAULT_CHANNEL || 'hos';
	redirect(`/${defaultChannel}`);
};
