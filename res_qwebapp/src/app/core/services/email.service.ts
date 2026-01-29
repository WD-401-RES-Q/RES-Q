import { Injectable } from '@angular/core';
import emailjs from '@emailjs/browser';

// EmailJS Configuration
// Sign up at https://www.emailjs.com/ and get your credentials
const EMAILJS_SERVICE_ID = 'service_yoyvzs4'; // Replace with your EmailJS service ID
const EMAILJS_TEMPLATE_ID = 'template_yekv4k9'; // Replace with your EmailJS template ID
const EMAILJS_PUBLIC_KEY = 'JLaponS_oi9inmIDR'; // Replace with your EmailJS public key

@Injectable({
  providedIn: 'root'
})
export class EmailService {

  constructor() {
    // Initialize EmailJS with your public key
    emailjs.init(EMAILJS_PUBLIC_KEY);
  }

  /**
   * Send account approval notification email
   * @param recipientEmail - The email address of the approved user
   * @param recipientName - The name of the approved user
   * @returns Promise that resolves when email is sent
   */
  async sendApprovalEmail(recipientEmail: string, recipientName: string): Promise<boolean> {
    try {
      console.log('Sending approval email to:', recipientEmail);

      const templateParams = {
        to_email: recipientEmail,
        to_name: recipientName,
        subject: 'RES-Q Account Approved',
        message: `Dear ${recipientName},\n\nGreat news! Your RES-Q account has been approved by our admin team.\n\nYou can now log in to the app using your registered phone number. If you haven't created your PIN yet, please use the "Forgot PIN?" option on the login screen to set up your PIN.\n\nThank you for joining RES-Q!\n\nBest regards,\nThe RES-Q Team`
      };

      const response = await emailjs.send(
        EMAILJS_SERVICE_ID,
        EMAILJS_TEMPLATE_ID,
        templateParams,
        EMAILJS_PUBLIC_KEY
      );

      console.log('Email sent successfully:', response);
      return true;
    } catch (error) {
      console.error('Failed to send approval email:', error);
      return false;
    }
  }

  /**
   * Send account rejection notification email
   * @param recipientEmail - The email address of the rejected user
   * @param recipientName - The name of the rejected user
   * @param reason - The reason for rejection
   * @returns Promise that resolves when email is sent
   */
  async sendRejectionEmail(recipientEmail: string, recipientName: string, reason: string): Promise<boolean> {
    try {
      console.log('Sending rejection email to:', recipientEmail);

      const templateParams = {
        to_email: recipientEmail,
        to_name: recipientName,
        subject: 'RES-Q Account Application Update',
        message: `Dear ${recipientName},\n\nWe regret to inform you that your RES-Q account application has not been approved at this time.\n\nReason: ${reason}\n\nIf you believe this was a mistake or would like to reapply, please register again with valid information.\n\nBest regards,\nThe RES-Q Team`
      };

      const response = await emailjs.send(
        EMAILJS_SERVICE_ID,
        EMAILJS_TEMPLATE_ID,
        templateParams,
        EMAILJS_PUBLIC_KEY
      );

      console.log('Rejection email sent successfully:', response);
      return true;
    } catch (error) {
      console.error('Failed to send rejection email:', error);
      return false;
    }
  }
}
