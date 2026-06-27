import { Resend } from 'resend';

export async function sendEmailWithGif(email: string, gifUrl: string, apiKey: string): Promise<void> {
  const resend = new Resend(apiKey);

  const { error } = await resend.emails.send({
    from: 'Moment <onboarding@resend.dev>',
    to: email,
    subject: 'Your Moment Loop is Ready! 📸',
    html: `
      <div style="font-family: sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; background-color: #0d0b14; color: #ffffff; border-radius: 12px; text-align: center;">
        <h2 style="color: #a855f7; letter-spacing: 2px; font-weight: bold;">YOUR MOMENT IS READY</h2>
        <p style="color: #cccccc; font-size: 16px;">Thanks for visiting the multi-camera photo booth. Your looping ping-pong animation is attached and available below:</p>
        <div style="margin: 30px 0;">
          <img src="${gifUrl}" alt="Your Loop" style="max-width: 100%; border-radius: 8px; border: 2px solid #a855f7;" />
        </div>
        <p style="font-size: 14px; margin-top: 30px;"><a href="${gifUrl}" style="color: #3b82f6; text-decoration: none; font-weight: bold;">Download Direct Link</a></p>
      </div>
    `,
  });

  if (error) {
    throw new Error(`Resend email error: ${error.message}`);
  }
}
