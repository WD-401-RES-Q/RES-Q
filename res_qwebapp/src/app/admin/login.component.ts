import { Component, signal, OnInit, OnDestroy } from '@angular/core';
import { Router } from '@angular/router';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AuthService } from '../services/auth.service';

@Component({
  selector: 'app-admin-login',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './login.component.html',
  styleUrls: ['./login.component.css']
})
export class AdminLoginComponent implements OnInit, OnDestroy {

  username = '';
  password = '';
  errorMessage = signal('');
  isLoading = signal(false);

  constructor(
    private authService: AuthService,
    private router: Router
  ) {}

  /* ==========================================================
     DISABLE SCROLLING (LOGIN PAGE ONLY)
     ========================================================== */
  ngOnInit(): void {
    document.body.classList.add('login-no-scroll');
  }

  ngOnDestroy(): void {
    document.body.classList.remove('login-no-scroll');
  }

  /* ==========================================================
     LOGIN HANDLER
     ========================================================== */
  async onSubmit(): Promise<void> {
    this.errorMessage.set('');

    if (!this.username || !this.password) {
      this.errorMessage.set('Please enter both username and password');
      return;
    }

    this.isLoading.set(true);

    try {
      const success = await this.authService.login(
        this.username,
        this.password
      );

      if (success) {
        this.router.navigate(['/admin/dashboard']);
      } else {
        this.errorMessage.set('Invalid username or password');
      }
    } catch (error) {
      this.errorMessage.set('An error occurred. Please try again.');
      console.error('Login error:', error);
    } finally {
      this.isLoading.set(false);
    }
  }
}
