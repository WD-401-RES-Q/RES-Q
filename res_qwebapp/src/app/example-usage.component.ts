// Example of how to use Firestore in your Angular components

import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FirestoreService } from './firestore.service';

@Component({
  selector: 'app-example',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div>
      <h2>Firestore Connection Example</h2>
      
      <h3>Users:</h3>
      <ul>
        <li *ngFor="let user of users">
          {{ user.username }} - {{ user.email }}
        </li>
      </ul>

      <h3>Semi Admins:</h3>
      <ul>
        <li *ngFor="let admin of semiAdmins">
          {{ admin.username }}
        </li>
      </ul>
    </div>
  `
})
export class ExampleComponent implements OnInit {
  users: any[] = [];
  semiAdmins: any[] = [];

  constructor(private firestoreService: FirestoreService) {}

  async ngOnInit() {
    try {
      // Get all users
      this.users = await this.firestoreService.getUsers();
      console.log('Users:', this.users);

      // Get all semi admins
      this.semiAdmins = await this.firestoreService.getSemiAdmins();
      console.log('Semi Admins:', this.semiAdmins);

      // Example: Get a specific user by username
      const specificUser = await this.firestoreService.getUserByUsername('someusername');
      console.log('Specific user:', specificUser);

    } catch (error) {
      console.error('Error fetching data from Firestore:', error);
    }
  }

  // Example: Add a new user
  async addUser(userData: any) {
    try {
      const docId = await this.firestoreService.addDocument('users', userData);
      console.log('User added with ID:', docId);
    } catch (error) {
      console.error('Error adding user:', error);
    }
  }

  // Example: Update a user
  async updateUser(userId: string, updates: any) {
    try {
      await this.firestoreService.updateDocument('users', userId, updates);
      console.log('User updated successfully');
    } catch (error) {
      console.error('Error updating user:', error);
    }
  }
}
