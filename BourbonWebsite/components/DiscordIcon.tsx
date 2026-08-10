type DiscordIconProps = { size?: number };

export function DiscordIcon({ size = 20 }: DiscordIconProps) {
  return (
    <svg
      aria-hidden="true"
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M18.2 6.2A13.4 13.4 0 0 0 15 5.2l-.4.9a12.1 12.1 0 0 0-5.2 0L9 5.2a13.4 13.4 0 0 0-3.2 1C3.8 9.1 3.3 11.9 3.5 14.7a13.3 13.3 0 0 0 3.9 2l.9-1.3a8.5 8.5 0 0 1-1.4-.7l.4-.3c2.7 1.3 5.7 1.3 8.4 0l.4.3c-.5.3-.9.5-1.4.7l.9 1.3a13.3 13.3 0 0 0 3.9-2c.3-3.2-.5-6-1.8-8.5Z"
        fill="currentColor"
      />
      <circle cx="9.2" cy="11.2" r="1" fill="#0b1220" />
      <circle cx="14.8" cy="11.2" r="1" fill="#0b1220" />
    </svg>
  );
}
