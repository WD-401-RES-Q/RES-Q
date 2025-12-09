import { Component } from '@angular/core';
import { FormsModule } from '@angular/forms';

@Component({
  selector: 'app-settings',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './settings.html',
})
export class SettingsComponent {
  notifyEmail = true;
  notifySMS = false;

  save() {
    console.log('Save settings', {
      notifyEmail: this.notifyEmail,
      notifySMS: this.notifySMS,
    });
  }
}
