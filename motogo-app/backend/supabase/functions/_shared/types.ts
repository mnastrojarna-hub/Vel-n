/**
 * MotoGo24 — TypeScript typy pro Edge Functions request/response
 */

// ─── SOS ──────────────────────────────────────────────
export type SosType =
  | 'accident_minor'
  | 'accident_major'
  | 'theft'
  | 'breakdown_minor'
  | 'breakdown_major'
  | 'location_share';

export type SosStatus =
  | 'reported'
  | 'acknowledged'
  | 'in_progress'
  | 'resolved'
  | 'closed';

export interface SosIncident {
  id: string;
  user_id: string;
  booking_id: string;
  type: SosType;
  latitude: number;
  longitude: number;
  description: string;
  is_fault: boolean;
  status: SosStatus;
  created_at: string;
  customer_name: string;
  customer_phone: string;
  moto_model: string;
  moto_spz: string;
}

export interface SendSosRequest {
  incident_id: string;
}

export interface SendSosResponse {
  success: boolean;
  error?: string;
}

// ─── Payment ──────────────────────────────────────────
export type PaymentMethod = 'card' | 'cash' | 'transfer';

export interface PaymentRequest {
  booking_id: string;
  amount: number;
  method: PaymentMethod;
}

export interface PaymentResponse {
  success: boolean;
  checkout_url?: string;
  transaction_id?: string;
  amount: number;
  method: PaymentMethod;
  processed_at: string;
  error?: string;
}

export interface StripeWebhookEvent {
  id: string;
  type: string;
  data: {
    object: {
      id: string;
      metadata: {
        booking_id: string;
      };
      amount_total: number;
      payment_status: string;
    };
  };
}

// ─── Email ────────────────────────────────────────────
export type EmailTemplateType =
  | 'booking_confirmation'
  | 'booking_reminder'
  | 'sos_admin_alert'
  | 'document_send'
  | 'password_reset'
  | 'invoice_send';

export interface EmailRequest {
  type: EmailTemplateType;
  recipient_email: string;
  data: Record<string, unknown>;
}

export interface EmailResponse {
  success: boolean;
  message_id?: string;
  error?: string;
}

// ─── Upload ───────────────────────────────────────────
export type StorageBucket = 'documents' | 'media' | 'sos-photos';

export interface UploadResponse {
  success: boolean;
  url?: string;
  path?: string;
  size?: number;
  error?: string;
}

// ─── Admin Auth ───────────────────────────────────────
export type AdminRole = 'superadmin' | 'manager' | 'operator' | 'viewer';
export type AdminAction = 'login' | 'verify' | 'permissions';

export interface AdminAuthRequest {
  action: AdminAction;
}

export interface AdminPermissions {
  bookings: { read: boolean; write: boolean; delete: boolean };
  motorcycles: { read: boolean; write: boolean; delete: boolean };
  customers: { read: boolean; write: boolean; delete: boolean };
  finance: { read: boolean; write: boolean; delete: boolean };
  sos: { read: boolean; write: boolean; delete: boolean };
  settings: { read: boolean; write: boolean; delete: boolean };
  reports: { read: boolean; write: boolean; delete: boolean };
  ai_copilot: { read: boolean; write: boolean; delete: boolean };
}

export interface AdminAuthResponse {
  success: boolean;
  user?: {
    id: string;
    email: string;
    full_name: string;
  };
  role?: AdminRole;
  branch_access?: string[];
  permissions?: AdminPermissions;
  error?: string;
}

// ─── AI Copilot ───────────────────────────────────────
export type AiContextPage =
  | 'dashboard'
  | 'fleet'
  | 'finance'
  | 'bookings'
  | 'inventory'
  | 'sos'
  | 'customers'
  | 'reports';

export interface AiCopilotRequest {
  message: string;
  conversation_id?: string;
  context_page?: AiContextPage;
}

export interface AiAction {
  type: string;
  entity_type: string;
  entity_id?: string;
  payload: Record<string, unknown>;
}

export interface AiCopilotResponse {
  success: boolean;
  response?: string;
  actions?: AiAction[];
  conversation_id?: string;
  error?: string;
}

// ─── Document Generation ──────────────────────────────
export interface DocumentGenerateRequest {
  template_type: string;
  booking_id?: string;
  customer_id?: string;
  custom_data?: Record<string, unknown>;
}

export interface DocumentGenerateResponse {
  success: boolean;
  pdf_url?: string;
  document_id?: string;
  error?: string;
}

// ─── Reports ──────────────────────────────────────────
export type ReportType =
  | 'monthly'
  | 'annual'
  | 'pl'
  | 'balance_sheet'
  | 'cashflow'
  | 'moto_roi';

export type ExportFormat = 'json' | 'pdf' | 'xlsx' | 'csv' | 'xml';

export interface ReportRequest {
  type: ReportType;
  period_from: string;
  period_to: string;
  branch_id?: string;
  format?: ExportFormat;
}

export interface ReportResponse {
  success: boolean;
  data?: Record<string, unknown>;
  file_url?: string;
  error?: string;
}

// ─── Tax ──────────────────────────────────────────────
export type TaxType =
  | 'dph_monthly'
  | 'dph_quarterly'
  | 'dppo_annual'
  | 'kontrolni_hlaseni';

export interface TaxRequest {
  type: TaxType;
  period_from: string;
  period_to: string;
}

export interface TaxResponse {
  success: boolean;
  data?: Record<string, unknown>;
  xml?: string;
  tax_record_id?: string;
  error?: string;
}

// ─── Export ───────────────────────────────────────────
export type ExportDataType =
  | 'bookings'
  | 'motorcycles'
  | 'customers'
  | 'invoices'
  | 'accounting'
  | 'inventory'
  | 'sos';

export interface ExportFilters {
  date_from?: string;
  date_to?: string;
  branch_id?: string;
  status?: string;
}

export interface ExportRequest {
  data_type: ExportDataType;
  format: ExportFormat;
  filters?: ExportFilters;
}

export interface ExportResponse {
  success: boolean;
  file_url?: string;
  data?: unknown;
  error?: string;
}

// ─── Prediction ───────────────────────────────────────
export type PredictionType = 'demand' | 'revenue' | 'maintenance' | 'stock';

export interface PredictionRequest {
  type: PredictionType;
  period_months: number;
  branch_id?: string;
}

export interface PredictionResponse {
  success: boolean;
  predictions?: Array<{
    month: string;
    value: number;
    confidence: number;
  }>;
  error?: string;
}

// ─── Inventory Check ─────────────────────────────────
export interface InventoryCheckResponse {
  success: boolean;
  items_below_min: number;
  orders_created: number;
  error?: string;
}

// ─── Cron ─────────────────────────────────────────────
export interface CronResult {
  success: boolean;
  tasks: Array<{
    name: string;
    status: 'ok' | 'error';
    detail?: string;
  }>;
  error?: string;
}

// ─── Webhook ──────────────────────────────────────────
export type WebhookSource = 'stripe' | 'whatsapp' | 'instagram';

export interface WebhookResponse {
  success: boolean;
  processed: boolean;
  error?: string;
}

// ─── CMS Sync ─────────────────────────────────────────
export interface CmsSyncRequest {
  keys?: string[];
}

export interface CmsSyncResponse {
  success: boolean;
  variables?: Record<string, unknown>;
  error?: string;
}
